# Automation and Orchestration

The goal of this project is walk an end-to-end path of continuous integration with both application and infrastructure code, and to do so at a low enough level that the impact of design and tooling choices can be seen.

A few questions I want to answer:
* What is the scope of "complete" task?
* What should be completely dynamic versus what should be statically configured.  For example, deploying into EC2 as opposed to a local Vagrant instance.  Should one job be capable of either?
* When static configuration does makes sense, how to externalize and encapsulate it?  
* How to manage and secure credentials used throughout the process?

Other questions revolve around tool selection, and the ways an infrastructure CI pipeline may differ from application pipeline.

## Objectives

At a super-high level, here's what I want:

1. A CI Pipeline for Infrastructure Code
When someone checks in infrastructure code:
Run lint tests
Run unit tests
Run post-convergence tests
Tag builds that pass for use in application testing
(?) Trigger a code review
(?) Update policies in authoritative Chef Server

2. A CI Pipeline for Application Code
When someone checks in application code and/or deployment code:
Run lint tests
Run unit tests
Deploy onto freshly-built VM
Run integration tests
Deploy latest known-good build onto freshly-built VM
Upgrade to latest using latest deployment code
Run integration tests

3. CI Pipeline Configuration
Code I can use to rapidly create CI infrastructure, itself:  
Build servers
Chef environment
Credential management
Event and log management

## Design Goals

* Realistic - No skipping the hard problems (such as credential management)
* Reuse.  As a consultant, I place a higher premium on re-use than people who live in the same organization for years at a time.  What is worthwhile for me to automate may not be the same things that it's worth any one of my clients to pay me to automate.
* Portability and modularity
* Transparency
* Secure credential management
* A balance between central control and security isolation that can pass scrutiny from a Compliance team.


## Environment

A quick listing of the tool selections I've made:

| CI Capability                    | Tool Selection
| ---------------------------------|---------------------
| Source Control                   | GitHub
| Infrastructure Automation        | Chef (server mode, rather than solo)
| Build Server                     | Jenkins
| Base OS                          | Ubuntu 12.04
| Infrastructure Test Harness      | Test-Kitchen
| Post-Convergence Tests           | ServerSpec
| Infrastructure Code Lint Tests   | FoodCritic
| Infrastructure Code Unit Tests   | ChefSpec
| Local Workstation VM Provider    | Vagrant + VirtualBox
| Shared VM Provider               | AWS + CloudFormation
| Application Deployment           | Chef
| Application Testing Framework    | Rake + Rspec + Capybara


These tools have some dependencies I've not listed.
They can be put together in many different ways to accomplish the goals I've described.
I'll explain the underpinnings and my design decisions as we come to them.

_A Dirty Little Secret:_  Sometimes, the reason I do something a particular way is, "That's how I got it to work."


## Environment Illustrated

Diagram Here

## Managing Secrets

One of the thorniest constraints to resolve in a CI process is the secure handling of keys.
Automating processes means embedding tools with the ability to take sensitive actions.  
For example, to launch and destroy instances in AWS, or to connect services that comprise an application.

I have a few tenets for managing secrets:
* Do no harm.  Manage secrets at least as securely as existing practices in the organization; improve on them if you can.  
* If possible, protect secrets with authenticated access control and encryption.
* Require both authentication and authorization to use a key.
* Limit the privileges associated with credentials.
* Monitor keys for abuse.

How I implement these tenets can vary, but a good place to start is by mapping the constraints.

CI nodes need:
* Login credential to access slave node
* Code checkout credential(s)
* Provider credential to launch integration test nodes
* Login credential to access integration test nodes

Test nodes need:
* Service credentials for the software they run
* Service credentials for external services they call (i.e. any services not controlled by the CI pipeline).
* Code deployment credential(s)

My layout is such that, for any given "stack", or grouping of CI nodes and target environment:
* Chef Server holds the secrets in a vault.
* The secrets in the vault include those listed above for CI nodes, plus a data bag key that can be sent to the test nodes.
* A chef server may hold multiple vaults, i.e. one per environment.
* For each vault, the chef server also holds an encrypted data bag.
* CI clusters (master-slave pairings) may support multiple environments, isolated by Jenkins and OS credentials and authorization; or be dedicated to a single environment.

In terms of a process:
1. CI servers obtain/sync their vaulted secrets when chef-client runs on the CI node.  The chef-client writes these to the filesystem.
2. When a CI job starts, Jenkins injects the secrets into the job environment.
3. Test-kitchen uses the environment values to launch and bootstrap the target node.
4. The chef-client on the target node uses the shared secret to retrieve and decrypt the data bag associated with its environment.  

The above layout and process give me logical and cryptographic isolation of secrets.  I can always reduce the separation if I'm less security-sensitive, but at the moment:
* Only the CI servers can access the AWS console key.
* Data bags and keys are per-environment.
* I avoid the complication of using vault with elastic environments.

Let's be clear: I'm trusting the CI nodes.  I'm putting several secrets on them that confer great power, and I'm doing nothing to encrypt them, once those secrets are on the filesystem.  

The implications of this trust, however, are that I'll need to take steps to:
* Ensure the CI nodes are trustworthy
* Limit the capabilities associated with different keys
* Monitor keys for abuse

In my experience, most shops eventually trust a server in this manner somewhere, so in general I expect to meet my "do no harm" rule.  And if an organization I'm working with has adopted a more stringent protocol, I'm pretty sure I can integrate the above with it.

## CI, Yes.  CD?

Probably not.  The bar is simply too high to warrant starting out with a goal of CD.  Put another way, CD is way beyond the minimum viable product of CI.  But a one-button deployment?  Absolutely.

## Chef Server

While you can devise a similar workflow based on Chef Solo, I think Chef Server has a number of advantages, particularly as the complexity of an infrastructure and the number of "cooks in the kitchen" increases.  These advantages include search, separation of duties, and reporting, and you can read more about them elsewhere.

The principle downsides to Chef Server in a development context have been the overhead and latency of uploading policy changes before you can test them.  And in a CI context, the challenge of keeping nodes and clients current, given an ever-changing set of transient test nodes.

I want to use Chef Server, but no single location seems likely to meet all my requirements:
* Hosted is only available when I'm online, plus I have the network overhead.
* Chef-zero on my laptop (or, say, the Jenkins slave running as a VM on my laptop) isn't reachable by the target node if that node is in AWS.
* Chef-zero on the target node (as initialized by Test Kitchen) requires a lot of faking and stubbing if I want to test multiple nodes in concert.
* No option using chef-zero is viable as a Production solution.

On the other hand, it's pretty easy to programmatically load objects into chef server, and I can point to a chef server based on environment settings.  If I let nodes populate themselves on bootstrap, I can load cookbooks, roles, environments and data bags by script.  This should give me both consistent policies and flexibility.  The biggest complication will be if I want to re-point the CI nodes from one Chef instance to another.  I think I can manage that pretty easily by re-bootstrapping them.

As a side-benefit, if I'm concerned about controlling access to my authoritative chef server(s), loading programmitically (and, say, triggering it based on a git check-in and tag) is right in line with the goal locking down that access.

When you think about your own Chef Server layout, make sure you know how workstations and managed nodes in various locations will be able to access it.  NATs and network ACLs can play havoc with CI plans.

## Directory & Repo Structure

Immediately when setting up the project, I have to decide on the structure of directories and source code repositories.  I've opted for several small repositories: Partly because it's consistent with the approach for a DVCS like git; also because I think it will map reasonably well to divisions of labor and variations in the lifecycle of different code modules.

```
ci-demo/                  # repo = ci-demo
  cfn-templates           # repo = ci-demo
  chef-repo/              # standalone repo
  cookbooks/              # not in any repo
    build_master/         # standalone repo
    rails_infrastructure  # standalone repo
  doc/                    # repo = ci-demo
  rails_projects/         # not in any repo
    demo_app/             # standalone repo
  vagrant                 # repo = ci-demo
```

A few comments about this structure:
* There are no submodules.  Where one repo lives inside a directory that's in another repo (e.g. chef-repo within ci-demo), the higher-level repo has a .gitignore entry to ignore the lower-level one.
* I've included the sensitive files for Chef -- .pem files and a data bag encryption key -- in the chef-repo repository.  This is acceptable because they're only used with a local, transient chef server instance (Chef Zero), and they've been named to avoid any chance of being mistaken as genuinely secure keys.  I would _not_ handle keys in this manner if using a persistent Chef server.

## Jenkins

The initial setup of Jenkins is intended to be simple but reasonable:
* HTTPS with self-signed certificate
* Authentication enabled with a default user defined
* Master and single slave

Jobs will be created manually.
Credentials (used with jobs and slaves) will be created through data bags.  This means that recipes can remain unchanged even as additional job credentials are required.
Converging policies (running chef-client) on Jenkins nodes won't conflict with job definitions.

I have a cookbook that does this (more or less) already, although I will need to modify it to set up a slave server: https://github.com/level11-cookbooks/build-master.

I'm going to set up Jenkins on local Vagrant VMs.  This is ideal for my immediate purposes (prototype and document), and should require few changes when shifting to a shared CI infrastructure.  It also satisfies the consideration that, in a pipeline where VMs are dynamically provisioned and destroyed, the CI controller has to be able to drive the API of the
VM provider, where ever it is.

Slaves run build and test jobs.
They need to be provisioned with the requirements for Jenkins, testing tools, and the applications they build & test.
As a matter of principle, slaves should also be as like their "real" server counterparts as feasible.
Slave configurations will therefore be tailored to individual application stacks, rather than being set up as universal "Swiss army knives" that can test any application, whether it be Node.js, Ruby, Java, C++, or whatever.
As long as resource considerations allow, I can run all the jobs for a given project (or multiple projects that use the same stack) on a single slave.  
With Rails and Chef both based on Ruby, I intend to run the jobs for both the application and infrastructure projects on the same slave node.
Note, however, that while all _jobs_ will run on the same slave, all _tests_ will not.  Lint and unit tests run directly on the slave node.  For integration tests, however, I want nodes that look _exactly_ like production -- i.e. no extra runtimes or libraries to support Jenkins or testing tools.  This means that for integration tests, the slave will launch one or more separate VMs and execute tests against them, remotely.


TODO: Fix security (see recipe note)
If you aren't familiar with Jenkins' master/slave topology, you can read about it here: https://wiki.jenkins-ci.org/display/JENKINS/Distributed+builds.

When you create a job, don't put spaces in the name.  It gets used in the workspace path.

Using Jenkins 1.55 and war-based install, per recommendation of jenkins cookbook on supermarket.getchef.com (which also using).

## Vagrant

You'll recall from the directory structure I described earlier, I've put Vagrant configurations into their own directory, outside of both chef-repo and cookbooks.  This decision stems in part from my desire for transparency in how different tools interact.  At least in this exercise, I want to control the lifecycle of Vagrant VMs and manage their definitions in a common place.  When I put a Vagrantfile inside a cookbook, I start getting confused:
* Test-Kitchen uses Vagrant but doesn't read the Vagrantfile.
* If you run ```berks init``` Berkshelf tries to create its own Vagrantfile.

The Vagrantfile is set up so that it can have multiple machines defined.  All the VMs share a common, private network, 192.168.43.0/24, and have a statically assigned IP address.  This hardcoding of network information is one of the things in my approach that I'm not sure about.  It obviously has potential to break down at some point, but I'm not yet sure where that will be, so I've left it for now.  The nodes I've defined are:

* buildmaster - a persistent jenkins master, part of CI pipeline
* buildslave01 - a persistent slave node, part of CI pipeline
* rdev  - ruby on rails development environment; chefdk or equivalent also installed
* rtest - ruby on rails "pre-commit" test environment; chefdk or equivalent also installed
* scratch - a node that can be launched and torn down as part of integration tests

One other aspect of my Luddite usage of Vagrant: I'm not using any provisioner, for a combination of reasons:
* If using chef-client, Vagrant doesn't create a client.rb file in the node  (by design -- see https://github.com/mitchellh/vagrant/issues/1145).  This means you can't just run 'sudo chef-client' from within the node.  I could run ```vagrant provision``` but I don't like that so much.
* If using chef_solo, I would want to use berkshelf, but the berkshelf-vagrant plugin doesn't currently support a multi-machine vagrant file.
* If using chef_zero, vagrant controls the setup and teardown of the server, and I presume does so with a single VM in mind.  I want to use my server across the multiple machines, so I want to control its life cycle.
* I expect to control provisioning during automated tests using Test Kitchen.

### Version & Plugins
I've been bitten by version incompatibilities between Vagrant and other tools in the Chef ecosystem.  FYI, this is what I'm using:
* Version: 1.6.3
* Plugins: vagrant-omnibus, vagrant-berkshelf

### Vagrant & SSH

Rather than relying on ```vagrant ssh``` which only works when Vagrant can find its configuration file, I've created entries for the Vagrant VMs in my ~/.ssh/config file.  This gives me quicker & more flexible access to VMs.  An example from my .ssh/config is below:

```
Host scratch
	HostName 192.168.43.6
	User vagrant
	IdentityFile /Users/normseth/.vagrant.d/insecure_private_key
````

## Amazon Web Services

I expect to use a combination of Vagrant VMs and EC2 instances for integration testing: Vagrant when working in "development mode", but ultimately I want my CI pipeline to extend into EC2.  In addition, if I extend this article to encompass Production deployments, I expect to host that environment in AWS.

To this end, I've described a simple network layout in EC2 using CloudFormation.  This conveniently encapsulates and isolates my working environment.  It's also something I can easily plug into a Jenkins job, later on, although initially I've just created it through the AWS CLI tools.




## Chef Layout & Configuration
```
demo-v2/
  chef-repo/
    .chef/      # These hold different configurations.  This one for ci jobs
  cookbooks/
  .chef/        # This one for persistent infrastructure
```

The above is a little awkward in part because haven't separated out the credential databags yet.  Working around by using -c flag to change knife config while loading same source files.

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

## Testing
My test "harness" for infrastructure code includes the following:
* Rspec - Foundational tool for testing ruby code
* ChefSpec - Unit testing tool for Chef; depends on Rspec
* ServerSpec - Testing tool for server configuration; depends on Rspec
* Test Kitchen - Orchestration tool for testing infrastructure code on multiple platforms and providers

For application code, I've simply followed the tools employed in the tutorial:
* Rspec
* Capybara

Comprehensive testing requires multiple types of test: static analysis, unit, integration.
Where and how these are run varies, both by the type of test and whether the code being tested is infrastructure or application code.
Static and unit tests can run on a Jenkins node.

For integration tests, I want the node being tested as close to "reality" as possible.  This means executing tests on Jenkins node against a remote node that doesn't have the Jenkins agent, or any other requisites installed on it.  As an aside, while this type of execution is a preference for a single-node integration test, it becomes increasingly important when it comes to multi-node integration and/or performance tests.



## Application Environment

The first demo application is going to be a rails application.
My development environment -- and later on, test and production -- are VMs running the rails stack.
The "narrative" that parallels this reference describes first the manual and later the chef-driven configuration.  The final chef run-list (plus related items) looks like:
TODO: Document chef runlist, roles, env, data bags, etc.

## Demo Application

The demo application comes directly from www.railstutorial.org.
My github repo is normseth/microblog_ruby.
TODO: Get database credentials out of database.yml.  Maybe add database.yml to .gitignore.

## Monitoring for Credential Abuse

## Questions About This Approach

The approach I've described through this article raises some natural questions.  For some, I have ready answers, for others, less so.

* The two-server approach seems to ignore the capabilities of Chef environments.  Why not use environments, instead?
* What about using Docker containers, rather than standalone VMs, for integration tests?
* Why not move Vagrant to the root of the project, so that ```vagrant ssh``` works from anywhere within the project?  (Answer: You're right but I'm a compulsive organizer and I like the clean root directory.)
