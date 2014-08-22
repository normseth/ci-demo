## Assumptions

Ubuntu 12.04 LTS as platform for all nodes.

## Directory & Repo Structure

Git repo and directory structure shown below.  No sub-repos or symlinking to fake things out.  May refactor later.
```
demo-v2/            # repo = demo-v2
  chef-repo/        # repo = demo-v2
  .chef/            # repo = demo-v2
  cookbooks/        # not in any repo
    build_master/   # standalone repo
  doc/              # repo = demo-v2
  rails_projects/   # not in any repo
    demo_app/       # standalone repo
```

Directories not included in the repo have been listed in .gitignore file.
The rails_projects directory is shared with the 'target' VM where I'm messing around with rails.

## Vagrant

Version: 1.6.3
Plugins: vagrant-omnibus
  Install with ``` vagrant plugin install vagrant-omnibus```.
  Installs chef on VM

The Vagrantfile is set up so that it can have multiple machines defined.  All the VMs share a common, private network, 192.168.43.0/24.  The VM host (my laptop) gets the first address in the range, which I use later as the address on which chef-zero listens.  The list of hosts is:

* buildmaster
* buildslave01
* rdev  # ruby on rails development environment
* rtest # ruby on rails test environment

## Chef Layout & Configuration
```
demo-v2/
  chef-repo/
  cookbooks/
  .chef/
```

knife.rb is standard as generated for organization from web UI.  The only change I've made are to:
* control chef_server_url based on an environment variable, for use with chef-zero  
* set values for copyright & author

Have located .chef above the repo so it's available both from chef-repo and cookbooks.  

Note: I'm aware that berkshelf-chef-vagrant integration might allow me to have these components work together "as magic" (possibly including Test-Kitchen, too).  However, I've had some problems with this orchestration in the past, and am inclined to stick to explicit orchestration in this first iteration of the demo, both for simplicity and transparency.

### Chef Zero
I have an organization set up within hosted Chef for the sake of demonstration, but when developing, I generally use chef-zero.  As mentioned above, I've not connected Chef as a provisioner into Vagrant.  Rather, my knife.rb conditionalizes the value of chef_server_url on the presence of the environment variable CHEF_ZERO and chooses between the two servers, accordingly.  

When launching chef-zero, I pass in ```--host 192.168.43.1``` so that it listens on the private network shared with the project VMs.

I've also installed the gem 'knife-backup' which I can use to easily back up and restore the state of my chef-zero server.

## Berkshelf

Berkshelf should be using knife configuration, nothing modified or added.
Generally, I create cookbooks with knife and copy a default Berksfile into place:

```
source "https://supermarket.getchef.com"

metadata
```

One optional practice I'm not following is a Berksfile above the cookbook directories that is, in essence, a superset of the per-cookbook files.  If you create such a file, you need to make sure it doesn't have a ```metadata``` entry.


## Jenkins

The initial setup of Jenkins is intended to be simple but reasonable:
* HTTPS with self-signed certificate
* Authentication enabled with a default user defined
* Master and single slave

I have a cookbook that does this (more or less) already, although I will need to modify it to set up a slave server: https://github.com/level11-cookbooks/build-master.

TODO: Understand and document the orchestration necessary to ensure master and slave are both up and connected.
If you aren't familiar with Jenkins' master/slave topology, you can read about it here: https://wiki.jenkins-ci.org/display/JENKINS/Distributed+builds.

## Application Environment

The first demo application is going to be a rails application.
My development environment -- and later on, test and production -- are VMs running the rails stack.
The "narrative" that parallels this reference describes first the manual and later the chef-driven configuration.  The final chef run-list (plus related items) looks like:
TODO: Document chef runlist, roles, env, data bags, etc.

## Demo Application

The demo application comes directly from www.railstutorial.org.
My github repo is normseth/microblog_ruby.
TODO: Get database credentials out of database.yml.  Maybe add database.yml to .gitignore.
