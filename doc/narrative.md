## Planning
Write down objectives & design goals
Make first passes at design described in readme.
* secrets
* chef server
* jenkins topo
* directory & git layout
* tool selection
* application design
Note that what you read there at this point has been through several iterations.
That is, don't expect a strictly linear progression through the design process for your own project.


## Setting up CI Infrastructure
Make sure I have Chef and related tools on my workstation (via ChefDK).
Go ahead and make ChefDK my default ruby/chef environment using chef-shell-init.
Make sure I have both Vagrant and AWS images for Ubuntu 12.04.
Make note to self to single-source these from Packer in a future iteration.
Set up project directory structure
Initialize git and set up exclusions in .gitignore.
Define VMs in a common Vagrantfile:
* buildmaster
* buildslave01
* scratch (a VM I'll use for working out various issues)
Make entries in .ssh/config.
Launch the build* VMs.
Set up hosted chef server/organization.  
Bootstrap with an empty run list.  
```
knife bootstrap master -x vagrant -P vagrant --sudo -N buildmaster
knife bootstrap slave01 -x vagrant -P vagrant --sudo -N buildslave01
```

Create environments.  
I'm thinking about two environments at this stage, 'ci' and 'test'.
I define the environments in JSON files, so they load more easily into chef-zero.
From there, I create them in the chef server:
```
# Assumes I'm in chef-repo directory
knife environment from file ci.json -c ../../.chef/knife.rb
knife environment from file test.json -c ../../.chef/knife.rb
```

Now, assign the build nodes to the 'ci' environment:
```
knife node environment_set buildmaster ci
knife node environment_set buildslave01 ci
```

Clone buildserver into cookbooks directory.  (Already had this cookbook pretty close to what I want.)

### Create vaults, data bags, keys, per design.

First, just generate and/or collect the secrets into a common location.

  _Jenkins Authentication Keypair_
  ```
  openssl genrsa -des3 -out jenkins_crypt.pem 2048            # generates password-encrypted key
  openssl rsa -in jenkins_crypt.pem -out jenkins.pem          # strips password and encryption for private key
  openssl rsa -in jenkins.pem -pubout -out jenkins_pub.pem    # outputs public key
  ```

  _Slave Login Credential_
  ```
  ssh-keygen -t rsa -C devops@level11.com                     # no passphrase, written to ./jenkins_buildslave
  ```

  _Code Checkout Credentials_
  I've decided on creating a GitHub machine credential, rather than a deploy key.  This has two advantages for me:
  * The same credential can access many repositories.
  * Access can be read/write or read-only.
  Generate a key with the following command.
  ```
  ssh-keygen -t rsa -C devops@level11.com                     # no passphrase, written to ./jenkins_github  
  ```
  Create a user account in GitHub.  I've named it 'level11-jenkins'.
  Add the SSH key to the account.
  Add level11-jenkins as a collaborator on the rails_infrastructure and ci-chef-repo repositories that I've created.


  _VM Provider Console_
  Using an existing SSH key for EC2.  I've formatted it into the file secrets/aws-environment as below:
  ```
  export AWS_ACCESS_KEY="AKI..."
  export AWS_SECRET_KEY="M+4Z.............."
  ```
  For Vagrant, I could enable SSH into my laptop and let Jenkins launch a VM.  But for now, I plan to just create and destroy local integration nodes manually.  

  _Integration Node Login Credential_
  For EC2, using an existing keypair.
  For Vagrant, using the Vagrant "insecure private key"
  In each case, I've copied the file into secrets/ just to give me a common place to find them.

  _Data Bag Secret for Test Nodes_
  ```
  openssl rand -base64 512 | tr -d '\r\n' > test_env_data_bag_secret
  ```

Next, I've stubbed my data bag items.  I've structured them to work with the chef-sugar method 'encrypted_data_bag_item_for_environment', even though I don't think I'm going to use that method.  It's minimal overhead and it also gives me a json structure that will let me store multiple environments in a single data bag item, when appropriate.

Contents of secrets/ci_creds.json
```
{
  "id": "ci_creds",
  "ci": {
    "jenkins_private_key": "",
    "jenkins_public_key": "",
    "jenkins_github_private_key": "",
    "jenkins_slave_login_private_key": "",
    "jenkins_slave_login_public_key": "",
    "aws_access_key": "",
    "aws_secret_access_key": "",
    "aws_keypair_id": "",
    "aws_keypair_secret": "",
    "vagrant_insecure_private_key": "",
    "test_env_data_bag_secret": ""
  }
}
```

Contents of secrets/microblog_creds.json
```
{
  "id": "microblog_creds",
  "integration-test": {
    "jenkins_github_private_key": "",
    "service_xxx_private_key": "another_secret_here"
  }
}
```

Populate the value for each key with the appropriate value generated earlier.
```
cat filename | sed s/$/\\\\n/ | tr -d '\n'
```
The above will give you the file contents in a format that can be pasted into a single string in json, and rendered correctly by Chef when referenced in a recipe.

Note that if you have an Amazon-generated keypair, you might need to strip line feeds from it, too, e.g.
```
cat filename | tr -d '\r' | sed s/$/\\\\n/ | tr -d '\n'
```

Create the creds data bag and the microblog_creds item.
```
knife data bag create creds
knife data bag from file creds ./microblog_creds.json --secret-file ./test_env_data_bag_secret
```

Use vault to create the ci_creds item.
```
knife vault create creds ci_creds -J ./ci_creds.json -S "chef_environment:ci" -M client -A normseth
```

### Enable Moving Between Chef Server Instances
This isn't really in the critical path for setting up a functioning pipeline, but as I've explained elsewhere, being able to move between a hosted Chef instance and a local instance of chef-zero should improve both flexibility and productivity.

First, the setup steps:
1. Export nodes and clients as JSON.
2. Export vaults and data bags (in their encrypted forms) as JSON.

```
# current directory is chef-repo
mkdir nodes clients
knife client show buildmaster -Fj > clients/buildmaster.json
knife client show buildslave01 -Fj > clients/buildslave01.json
knife node show buildmaster -lFj > nodes/buildmaster.json
knife node show buildslave01 -lFj > nodes/buildslave01.json
knife data bag show creds ci_creds -Fj > data_bags/creds/ci_creds.json
knife data bag show creds ci_creds_keys -Fj > data_bags/creds/ci_creds_keys.json
knife data bag show creds microblog_creds -Fj > data_bags/creds/microblog_creds.json
```

Then, to launch a local chef-zero, load it with data, and repoint both knife and the build server chef-clients at it:

```
# current directory is chef-repo
export CHEF_SERVER_IP=192.168.43.1    # knife.rb conditions chef_server_url on this variable
knife serve --chef-repo-path . --chef-zero-host $CHEF_SERVER_IP --chef-zero-port 8889 --repo-mode everything &
# update chef_server_url in /etc/chef/client.rb
```

I can basically reverse these steps to switch back to the hosted chef server.  Note, however, that if I destroy and recreate a node, I need to bootstrap it to the hosted chef organization first.

Lastly, as an aside: Even though the credentials are encrypted, I'm not going to push the exported data bags into the public GitHub repository.  So that I don't forget, I've added data_bags/creds to my .gitignore file.  If I were working in a private repository, I would both commit them locally and push them.  

Upload cookbooks with berks install / berks upload.

### Provisioning CI Nodes with Chef

You can find a couple commonly used cookbooks for Jenkins, if you search GitHub or the Chef Supermarket.
I'm using the 'jenkins' cookbook from Supermarket, by wrapping it in a cookbook I've called buildserver.
The source code is available and you should review the [readme](https://github.com/level11-cookbooks/buildserver) for information about it.  Incidentally, I've followed its recommendation to use the war-based install and Jenkins version 1.555.

At the end of the day, I have a two-node Jenkins cluster up & running.
* Master node has Jenkins and chef installed.
* Slave node has Jenkins agent requirements only, chef, and chef testing tools.
* Each node has secrets it needs per the design I've described.
* Jenkins credentials _have_ been created.
* Jenkins slave _has not_ been registered with the master.
* Jenkins jobs are not being created.

Jobs, as I've mentioned elsewhere, don't worry me much by their absence here: They are inherently bespoke, and can be exported pretty easily once stable, if you want to reuse them.

The slave node really should be registered with the master, but there seems to be an issue with the LWRP that interferes with my security configuration.  So for now, manual slave setup.  It's not a big deal, and any slaves so configured will survive future chef-client runs.

I used the following settings to define the slave through the Jenkins UI:


|Parameter        | Value                                               | Notes |
|-----------------|-----------------------------------------------------|-------|
|Name             | buildslave01                                        |       |
|Description      | Ubuntu 12.04 provisioned for ruby and chef testing  |       |
|Remote FS Root   | /var/jenkins                                        |Matches my slave recipe |  
|Labels           | chef ruby                                           |Will be used to tie jobs |
|Usage            | Tied jobs only                                      |       |
|Agent            | Launch by SSH                                       |       |
|Credential       | jenkins                                             | Created by master.rb and corresponds to user created by slave-ruby.rb |


One note regarding cookbook development: I went through many iterations of my buildserver cookbook, and ```berks upload``` will freeze your cookbooks in the Chef server.  For my local cookbook iteration I generally force the upload using ```knife cookbook upload COOKBOOK --force``` without bumping the cookbook version, until I have a version that is passing some basic smoke tests.  As code matures or I get into multi-user scenarios, I bump versions more frequently.

### Configuring Jobs?  Not Quite Yet.

Although a part of the CI configuration, the point of a job is to build and test code -- which I haven't written yet.  So nothing to do here, for now.  Instead, it's on to the infrastructure code to support a rails application.

## Creating Infrastructure & App Deployment Code

Given the design decisions I made about my rails stack, I have a pretty good notion of what I need to execute through Chef.  I'm going to factor this work into two cookbooks, one for the infrastructure and one for the application deployment.  I separate them because they seem best owned by different individuals (an admin and a developer).  They will also very likely evolve at different rates.  The developer may even want to move the deployment cookbook into her application code repository.

At the end of the day, I have cookbooks that
* Provision nodes by their role in the stack
* Deploy the application
* Include unit and integration tests

These are the cookbooks that will be used and tested by the CI jobs.

### Writing Unit Tests

### Writing Integration Tests

## Pipeline 1: Infrastructure Code

### Job 1: Static Tests

The only static tests I plan to use for Chef code is FoodCritic.  I could also add RuboCop or another ruby analyzer, but I don't see those adding as much value.

First, I need to define a parser for FoodCritic.  Read about this at http://acrmp.github.io/foodcritic under "Tracking Warnings Over Time".

Then define the job, using the Jenkins UI.  I applied the following settings:

|Parameter | Value | Notes |
|----------------------|--------------------------------------------------|------|
|Name                  | P01_J01_Rails_Infrastructure_Static_Tests        | Used in workspace directory name so avoid spaces |
|Description           | Run FoodCritic against Chef cookbook             | |
|GitHub Project        | https://github.com/normseth/rails_infrastructure | Used to link between jenkins job page and project page in GitHub |
|Discard old builds    | 15                                               | |
|Limit where run       | chef                                             | Matches one of the labels on the slave |
|Git repo              | git@github.com:normseth/rails_infrastructure.git | |
|Credential            | level11-jenkins                                  | Defined in vault & created by master.rb |
|Build Environment > Delete workspace before build starts | Yes | Ensures clean workspace but leaves things in place for troubleshooting failures |
|Build Steps > Execute Shell | PATH=/opt/chef/embedded/bin:$PATH foodcritic -f correctness . | |
|Post-Build Actions > Scan for compiler warnings | FoodCritic | | |

At this point, I'm not yet setting a build trigger.  Later on, I'll configure the job to poll for code updates.  

Try running it.

Two asides:
* Polling, rather than an event notification from GitHub, is a design tradeoff between the immediacy of starting the pipeline when code is updated, and security.  There is no single "right" answer, but given the sensitivity of the secrets I've entrusted to the CI nodes, I would rather not have them accepting events from outside my office firewall.

* I hit a low-level java error the first time I tried to run this job.  There was no obvious cause in the job log, so before trying to troubleshoot, I rebooted the slave and tried again.  All clean this time.  Haven't seen the problem reproduced since then, so not sure of cause or if could have been prevented.

### Job 2: Unit Tests

I'm using ChefSpec for Chef unit tests.  Installation of ChefSpec and its dependencies on the slave node was done in the buildserver::slave-ruby recipe, and the tests, themselves, I've also described elsewhere.  Many of the job settings are the same as those in the first job.

|Parameter | Value | Notes |
|----------------------|--------------------------------------------------|------|
|Name                  | P01_J02_Rails_Infrastructure_Unit_Tests          | |
|Description           | Run ChefSpec against Chef recipes                | |
|GitHub Project        | https://github.com/normseth/rails_infrastructure | Used to link between jenkins job page and project page in GitHub |
|Discard old builds    | 15                                               | |
|Limit where run       | chef                                             | |
|Git repo              | git@github.com:normseth/rails_infrastructure.git | |
|Credential            | level11-jenkins                                  | |
|Build Environment > Delete workspace before build starts | Yes | Ensures clean workspace but leaves things in place for troubleshooting failures |
|Build Steps > Execute Shell |PATH=/opt/chef/embedded/bin:$PATH rspec ./test/unit | | |

Later on, I'll configure the job to trigger integration tests, but only if unit tests complete successfully.

### Job 3: Post-Convergence Tests

In the context of automation testing, the terms "post-convergence test" and "integration test" are somewhat interchangeable.  Post-convergence is a little more explicit, in my mind, and I keep the term "integration" for tests that involve both the infrastructure and the deployed application.

This job is substantially more complex than the static and unit testing jobs, because although it will be controlled from the slave, it will be executed against a new VM that is launched on demand, by the job.  In addition, I'm actually defining two jobs that are variants of each other: One for testing in EC2 and the other for testing with a local Vagrant VM.

#### EC2 Version

|Parameter | Value | Notes |
|----------------------|--------------------------------------------------|------|
|Name                  | P01_J03_Rails_Infrastructure_PostConverge_EC2_Tests | |
|Description           | Run tests against converged node                | |
|GitHub Project        | https://github.com/normseth/rails_infrastructure | Used to link between jenkins job page and project page in GitHub |
|Discard old builds    | 15                                               | |
|Limit where run       | chef                                             | |
|Source Code Management | Multiple SCMs | Since using chef-zero, we need to check out the ci-chef-repo, as well as rails_infrastructure |
|Git repo              | git@github.com:normseth/rails_infrastructure.git | |
|Credential            | level11-jenkins                                  | |
|Additional Behaviors  | Check out to subdirectory         | cookbooks/rails_infrastructure |
|Git repo              | git@github.com:normseth/ci-chef-repo.git | |
|Credential            | level11-jenkins                                  | |
|Additional Behaviors  | Check out to subdirectory         | chef-repo |
|Build Triggers | None | Unit test job will trigger, but only if unit tests passed |
|Build Environment > Delete workspace before build starts | Yes | Ensures clean workspace but leaves things in place for troubleshooting failures |
|Build Environment > Inject Environment Variables > Properties File| /var/jenkins/.ssh/aws-environment | The values from this file are passed into Test Kitchen via the .kitchen.yml file.  Note that this properties file must exist on the slave node. |
|Build Environment > Inject Environment Variables > Properties Content | See Below | These are in addition to the sensitive values passed in via the properties file.  The subnet and security group IDs match those in the VPC I created earlier with CloudFormation. |
  ```
  PATH=/opt/chef/embedded/bin:$PATH
  SECURITY_GROUP_IDS=sg-048f1861  
  REGION=us-west-2
  AVAILABILITY_ZONE=us-west-2c
  SUBNET_ID=subnet-b79489f1
  DATA_BAG_SECRET_FILE
  ```

<!--
The properties file has the data that I'm most concerned about leaving around in cleartext.  
Could encrypt the file and parameterize the job.
http://serverfault.com/questions/489140/what-is-a-good-solution-to-encrypt-some-files-in-unix
-->

Build Step
  ```
  cd cookbooks/rails_infrastructure
  ln -s .kitchen.yml.ec2 .kitchen.yml
  kitchen test
  ```

<!--
ISSUE/WORKAROUND: Checkout to subdirectory only seems to work if all repos are checked out to subdir.
See https://issues.jenkins-ci.org/browse/JENKINS-23450  
This is actually okay for me, since that arrangement matches the layout of the project on my laptop.
Note that failed builds may leave cruft sitting in EC2.  
-->

This is the environment for the Vagrant version (also, no properties file)
TARGET_IP=192.168.43.6
TARGET_USERNAME=vagrant
TARGET_SSH_KEY=/var/jenkins/.ssh/insecure_vagrant_private_key

Once I have all three jobs working individually (four, counting both EC2 and Vagrant variants of the integration test) I want to go back and link them into a pipeline, using post-build steps.  I can run the pipeline through either Vagrant or EC2.
Have a standing VPC so not launching a stack as part of this job, but could -- and in later stage environments probably would.


Tag builds that pass for use in application testing
(?) Trigger a code review
(?) Update policies in authoritative Chef Server
Report results for failure at any step, and success at the end

## Pipeline 2: Application Code
