# Automation and Orchestration

The goal of this project is to walk an end-to-end path of continuous integration with both application and infrastructure code, and to do so at a low enough level that the impact of design and tooling choices can be seen.

A few questions I want to answer:
* What is the scope of "complete" task?
* What should be completely dynamic versus what should be statically configured.  For example, deploying into EC2 as opposed to a local Vagrant instance.  Should one job be capable of either?
* When static configuration does makes sense, how to externalize and encapsulate it?  
* How to manage and secure credentials used throughout the process?

Other questions revolve around tool selection, and the ways an infrastructure CI pipeline may differ from application pipeline.

This document is intended as a reference, describing the intent and finished state for various aspects of the project.  There is an accompanying narrative document that provides much more detail about how things were implemented.

## Objectives

At a super-high level, here's what I want:

<b>A CI Pipeline for Infrastructure Code

When someone checks in infrastructure code:
1. Run lint tests
2. Run unit tests
3. Run post-convergence tests
4. Tag builds that pass for use in application testing
5. (?) Trigger a code review
6. (?) Update policies in authoritative Chef Server

<b>A CI Pipeline for Application Code

When someone checks in application code and/or deployment code:
1. Run lint tests
2. Run unit tests
3. Deploy onto freshly-built VM
4. Run integration tests
5. Deploy latest known-good build onto freshly-built VM
6. Upgrade to latest using latest deployment code
7. Run integration tests

<b>CI Pipeline Provisioning

Code I can use to rapidly create CI infrastructure, itself:  
1. Build servers
2. Chef environment
3. Credential management
4. Event and log management

<b>(Future) Provision and Deploy to a Multi-Node Topology

## Design Goals

* Realistic - No skipping the hard problems (such as credential management)
* Reusable -  As a consultant, I place a higher premium on re-use than people who live in the same organization for years at a time.  Although I want to work at a detailed level here (where the devils usually lie) I am really interested in _patterns_.
* Portable and modular - Pull out and reuse only those aspects that are relevant to a customer.
* Transparent - Limit, for now, the reliance on built-in integration between tools (e.g. Berkshelf and Vagrant).
* Secure credential management - This seems to be skipped in most of the documentation I've found.
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
* Limit the privileges associated with credentials.
* Monitor keys for abuse.

How I implement these tenets can vary, but a good place to start is by mapping the constraints.

CI nodes need:
* Jenkins authentication keypair
* Login credential to access slave node
* Code checkout credential(s)
* Provider credential to launch integration test nodes
* Login credential to access integration test nodes
* The data bag encryption secret (only so it can be communicated to test nodes)

Test nodes need:
* Service credentials for the software they run
* Service credentials for external services they call (i.e. any services not controlled by the CI pipeline).
* Code deployment credential(s)
* Data bag decryption secret

My layout is such that, for any given "stack", or grouping of CI nodes and target environment:
* Chef Server holds the CI node secrets in a vault.  Note that a chef server may hold multiple vaults, encrypted to different sets of nodes.
* For each vault, the chef server also holds an encrypted data bag.  The data bag holds the secrets used by test nodes.
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

In my experience, most shops eventually trust a server in this manner somewhere, so in general I expect this approach to meet the "do no harm" rule.  And if an organization I'm working with has adopted a more stringent protocol, I'm pretty sure I can integrate the above with it.  

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

On the other hand, it's pretty easy to programmatically load objects into chef server, and I can point to a chef server based on environment settings.  This should make it pretty easy to switch between hosted enterprise and local chef zero instance, giving me both consistent policies and flexibility.  

I need to take two steps as preparation:
1. Export nodes and clients as JSON after bootstrapping.
2. Export vaults and data bags (in their encrypted forms) as JSON after uploading them.

Then, when I want to switch from hosted to local mode:
1. Start chef-zero using ```knife serve``` and load cookbooks, data bags, environments, nodes, clients and roles.
2. Change the chef_server_url value in /etc/chef/client.rb on the managed nodes.  

As a side-benefit, if I'm concerned about controlling access to my authoritative chef server(s), loading programmitically (and, say, triggering it based on a git check-in and tag) is right in line with the goal locking down that access.

When you think about your own Chef Server layout, make sure you know how workstations and managed nodes in various locations will be able to access it.  NATs and network ACLs can play havoc with CI plans.

## Directory & Repo Structure

Immediately when setting up the project, I have to decide on the structure of directories and source code repositories.  I've opted for several small repositories: Partly because it's consistent with the approach for a DVCS like git; also because I think it will map reasonably well to divisions of labor and variations in the lifecycle of different code modules.

```
ci-demo/                  # repo = ci-demo
  cfn-templates           # repo = ci-demo
  chef-repo/              # standalone repo
  cookbooks/              # not in any repo
    buildserver/          # standalone repo
    rails_infrastructure/ # standalone repo
    microblog_deploy/     # standalone repo
  doc/                    # repo = ci-demo
  rails_projects/         # not in any repo
    microblog/            # standalone repo
  secrets/                # not in any repo
    demo_app/             # standalone repo
  vagrant                 # repo = ci-demo
```

A couple comments about this structure:
* There are no submodules.  Where one repo lives inside a directory that's in another repo (e.g. chef-repo within ci-demo), the higher-level repo has a .gitignore entry to ignore the lower-level one.
TODO: Describe what sensitive data is/isn't included in source control, and how protected.
* I've created a symlink from from ci-demo/.chef/ to chef-repo/.chef/ so I can use knife from anywhere within the project, without having to specify a configuration file.  


## Jenkins

The initial setup of Jenkins is intended to be simple but consistent with the trusted status the CI servers require:
* HTTPS with self-signed certificate
* Authentication enabled with an admin user defined
* Master and single slave

Slaves execute the jobs to build and test code.  Slaves need to be provisioned with the requirements for Jenkins, testing tools, and the applications they will build & test.  If you aren't familiar with Jenkins' master/slave topology, you can read about it here: https://wiki.jenkins-ci.org/display/JENKINS/Distributed+builds.

As a matter of principle, slaves should also be as like their "real" server counterparts as feasible.  Slave configurations will therefore be tailored to individual application stacks, rather than being set up as universal "Swiss army knives" that can test any application, whether it be Node.js, Ruby, Java, C++, etc.

As long as resource considerations allow, I can run all the jobs for a given project (or multiple projects that use the same stack) on a single slave.  With Rails and Chef both based on Ruby, I intend to run the jobs for both the application and infrastructure projects on the same slave node.

Note, however, that while all _jobs_ will run on the same slave, all _tests_ will not.  Lint and unit tests run directly on the slave node.  For integration tests, however, I want nodes that look _exactly_ like production -- i.e. no extra runtimes or libraries to support Jenkins or testing tools.  So for integration tests, the slave will launch one or more separate VMs and execute tests against them, remotely.

Jobs will be created manually.  As a matter of reuse and documentation, I can "export" configured jobs into chef recipes.  This is a practice I'll follow once I have a job pretty well-baked.  Credentials, used with jobs and slaves, will be delivered through chef-vault, as discussed earlier. Converging policies (running chef-client) on Jenkins nodes won't conflict with job or slave definitions, even though these are not automated.

Jenkins nodes will be on local Vagrant VMs.  This is ideal for my immediate purposes (prototyping and documenting), but I'm not going to avail myself of all the integration "magic" between chef, berkshelf, and vagrant.  Doing so might make my implementation vagrant-specific in some ways, and interfere with re-using it in a shared environment with more persistent VMs.


## Vagrant

In the directory structure I described earlier, Vagrant configurations are in their own directory, outside of both chef-repo and cookbooks.  This decision stems in part from my desire for transparency in how different tools interact.  At least in this exercise, I want to control the lifecycle of Vagrant VMs and to manage their definitions in a common place.  Conversely, when I put a Vagrantfile inside a cookbook, I start getting confused:
* Test-Kitchen uses Vagrant but doesn't read the Vagrantfile.
* If you run ```berks init``` Berkshelf tries to create its own Vagrantfile.

My Vagrantfile is set up with multiple machines defined.  All the VMs share a common, private network, 192.168.43.0/24, and have a statically assigned IP address.  This hardcoding of network information is one of the things in my approach that I'd probably like to refactor, eventually.  It obviously has potential to break down at some point, but I'm not yet sure where that will be, so I've left it for now.  The nodes I've defined are:

* buildmaster - a persistent jenkins master, part of CI pipeline
* buildslave01 - a persistent slave node, part of CI pipeline
<!--
* rdev  - ruby on rails development environment; chefdk or equivalent also installed
* rtest - ruby on rails "pre-commit" test environment; chefdk or equivalent also installed
-->
* scratch - a node that can be launched and torn down as part of integration tests

One other aspect of my Luddite usage of Vagrant: I'm not using any provisioner, for a combination of reasons:
* If using chef-client, Vagrant doesn't create a client.rb file in the node  (by design -- see https://github.com/mitchellh/vagrant/issues/1145).  This means you can't just run 'sudo chef-client' from within the node.  I could run ```vagrant provision``` but I don't like that so much.
* If using chef_solo, I would want to use berkshelf, but the berkshelf-vagrant plugin doesn't currently support a multi-machine vagrant file.
* If using chef_zero, vagrant controls the setup and teardown of the server, and I presume does so with a single VM in mind.  I want to use my server across the multiple machines, so I want to control its life cycle.
* I expect to control provisioning during automated tests using Test Kitchen.

### Vagrant Version & Plugins
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

I expect to use a combination of Vagrant VMs and EC2 instances for integration testing: Vagrant when working in "development mode", but ultimately I want my CI pipeline to extend into EC2.  

To this end, I've described a simple network layout in EC2 using CloudFormation.  This conveniently encapsulates and isolates my working environment.  It's also something I can easily plug into a Jenkins job, later on, although initially I've just created it through the AWS CLI tools.

The template file is in ci-demo/cfn_templates.

## Berkshelf

I'm using Berkshelf to manage cookbook dependencies.
Berkshelf should be using knife configuration, nothing modified or added.
Generally, I create cookbooks with knife and copy a default Berksfile into place:

```
source "https://supermarket.getchef.com"

metadata
```

One optional practice I'm following is to maintain a Berksfile in cookbooks/, above the cookbook directories.  This file is essentially a superset of the per-cookbook files.  If you create such a file, you need to make sure it doesn't have a ```metadata``` entry.  Maintaining it goes against the DRY principle, but having it lets you generate a comprehensive view of all your cookbook dependencies using ```berks viz```.

## Application Architecture & Design

Application architecture and design are outside the scope of what I want to do in this project.
And they were largely resolved when I selected the application I was going to use as a demo.  
Different application languages, runtimes, architectures present different challenges for infrastructure automation.
Rails is a modern web-oriented framework, and the shared foundation of ruby for Rails and Chef is convenient.  But really any modern application stack would be a reasonable choice for prototyping a CI pipeline.
The demo application comes directly from www.railstutorial.org.
But in fact, when I start to work with the demo, I see that I do want to make changes.  The author wasn't thinking particularly about automation, or environment standardization, or other "ilities" that operations teams worry about.
Issues that arise when I start looking at the demo include:
* What database?
* Same database in all environments?
* Unicorn or Passenger?
* Which ruby?
* Assuming I'm happy with the author's recommendation of RVM, how install?

Without going into rationale, here's what I decided to implement:

## CI Pipelines

With all the infrastructure in place, a CI pipeline is essentially a series of related Jenkins jobs.
I want to define two pipelines, that although related, run independently and asynchronously.
If you look back at the high-level objectives I described for this project, you'll see these map very closely to those.

Diagram Infrastructure Pipeline Here

Diagram Application Pipeline Here

<!--
1. A CI Pipeline for Infrastructure Code
Poll for code change
Run lint tests
Run unit tests
Run post-convergence tests
Tag builds that pass for use in application testing
(?) Trigger a code review
(?) Update policies in authoritative Chef Server
Report results for failure at any step, and success at the end

2. A CI Pipeline for Application Code
Poll for code change
Run lint tests
Run unit tests
Deploy onto freshly-built VM
Run integration tests
Destroy VM
Deploy latest known-good build onto freshly-built VM
Upgrade to latest using latest deployment code
Run integration tests
Report results for failure at any step, and success at the end
-->

## Integration Testing with Test Kitchen

I have two scenarios I want to support:
* Testing against a node in EC2
* Testing against a local VM

The requirements for these scenarios are different enough that I won't try handle them in a single job.  Rather, I'll define a job for each, triggering the EC2 job via the pipeline, and leaving the local VM job to be run manually, when I need to use it.

How should this job (these jobs, really) interact with Chef?  Test Kitchen can use chef-zero, chef-solo, or chef-client as provisioner.  I've already steered away from chef-solo, but in my CI infrastructure I've set things up for both chef-zero and chef-client.  For this stage of testing, I've decided to use chef-zero: It guarantees the node gets all its code from the CI server, which in turn has gotten it from GitHub.  This is a decision that I probably make differently for later lifecycle environments (i.e. those closer to Production).  But before doing so I will want the uploading of policies into Chef Server also managed by this pipeline.  This aligns well with the idea of inserting a code review step later in the process.

## Situational Awareness

Automation means that things run unattended.  Humans get involved to deal with the exceptions.
To do so, we need to know about those exceptions, through tools like IRC, log centralization & analysis, event monitoring.  A CI pipeline -- any automation -- needs to hook into these tools.

### Monitoring for Credential Abuse

The first bit of situational awareness I want to address is improper use of the credentials that I've embedded into the CI pipeline.



## Questions

The approach I've described through this article raises some natural questions.  For some, I have ready answers, for others, less so.

* What about using Docker containers, rather than standalone VMs, for integration tests?
* Why not move Vagrant to the root of the project, so that ```vagrant ssh``` works from anywhere within the project?  (Answer: You're right but I'm a compulsive organizer and I like the clean root directory.)
* Whither test data?


## Additional Ideas
* Integration test over multiple nodes by chaining together several jobs that use kitchen verify
* Using chef-vault and chef server to create a secrets service where decrypted files aren't left on filesystem

## References

Information about different types of SSH access to GitHub
https://developer.github.com/guides/managing-deploy-keys/

How to generate SSH keys for GitHub
https://help.github.com/articles/generating-ssh-keys
