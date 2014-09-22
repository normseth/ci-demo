## Getting Started

### CI Infrastructure
Create a project directory.
Initialize git; set exclusions.
Define build-master and slave VMs in Vagrantfile.
Launch jenkins master and slave VMs.
Make entries in .ssh/config.
Create build-master in cookbooks directory.
Run berks install
If using chef zero
  Set environment for chef-zero
  Launch using knife serve
  Populates itself from chef-repo
  Run berks install / berks upload to get cookbooks & dependencies
  
  Bootstrapped manually with knife.
  Iterated over my cookbook, forcing the upload with knife as needed (not bumping version).

At the end of the day, I have a two-node Jenkins cluster up & running.
* Master node has Jenkins and chef installed.
* Slave node has Jenkins agent requirements only, chef, and chef testing tools.

## Open Issues
* Security for Jenkins.  Currently broken, but not blocking.  Issue is that my config-file hack gets over-written somewhere, and is fragile, in any case, because slaves are also configured in the same file.  Should fix by enabling security through Chef cookbook, but that means figuring out groovy syntax.

* kitchen-ec2 doesn't create ohai hint file.  Options include patching the gem, touching the file on the AMI,


When you combine all my design decisions and setup steps, here are the steps I go through to launch a jenkins slave:
cd vagrant
vagrant up buildslave01
cd ../cookbooks/build-master
berks install
berks upload
knife cookbook upload build-master --force
ssh slave01
knife bootstrap slave01 -x vagrant --sudo --run-list 'recipe[build-master::slave-ruby]' --environment ci --secret-file XXXXX
And once the node is up and converged, need to add it as slave in jenkins ui and tag it for chef jobs

### Application Development Environment
I could go straight to the community and find a cookbook to set up my rails stack, but I'm going to take a lower-level approach at first, to ensure I understand the infrastructure.  The gist is that I'm going to manually install the infrastructure on a fresh VM, capturing the steps in my command history file.  At the end, I'll distill it down to just the tasks I need to automate (skipping all digressions & mistakes), and build or borrow recipes to suit.  This will also help when I want to chef-ify the entire infrastructure, later.

I'm working from this document: http://www.railstutorial.org/book/beginning#sec-up_and_running

Here's my distilled command history, once I have my first application up & running.  At this point, this is just a development stack (aka group, as defined in first_app/Gemfile).  It also lacks two elements of the stack that are common, an application server and a load balancer.  These will come later.
```
sudo apt-get update
sudo apt-get install curl git -y
git config --global user.name "normseth"
git config --global user.email nik@ormseth.net
curl -sSL https://get.rvm.io | bash -s stable
source /home/vagrant/.rvm/scripts/rvm
rvm requirements
rvm install 2.0.0
rvm use 2.0.0@railstutorial_rails_4_0 --create --default
gem update --system 2.1.9
vi ~/.gemrc
gem install rails --version 4.0.8
sudo apt-get install libxslt-dev libxml2-dev libsqlite3-dev -y
cd /rails_projects/
rails new first_app
cd first_app/
vi Gemfile    # to set explicit gem versions
bundle update
bundle install
sudo apt-get install nodejs -y
rails server
```

From a browser on my laptop I can get to the app at http://192.168.43.4:3000
BTW, I'm sharing the folder in which I've created the application between my laptop and the VM, so I have access to the files from either machine.

Initialize a git repository, and set up a remote origin on GitHub.

I built the 'rdev' VM by hand to get some insight into the rails stack.

I also want an 'rtest' VM, to use for pre-commit testing.

To reinforce & further my understanding of rails, I'm going to set up the rtest VM manually.
The only difference I want is to use postgresql rather than sqlite.
I mostly follow the steps from the development setup, although I skip the steps for creating the app, since I'm going to deploy it to this VM via GitHub.  (Note that trying to share the files directly, as I've done between laptop and rdev, would be a mistake.  I'm going to have gem differences between these environments, so they will have different bundler configurations.  Rails configures git to ignore .bundle, which facilitates such differences when deploying.)

Add test group to Gemfile
Install packages postgresql and libpq-dev.
Run ```bundle install --without development``` to install the necessary gems.  In this case, I install pg and not sqlite3.

Create the credential that will be used with the database:
```
sudo su - postgres
psql
create role first_app with createdb login password 'password1';    # don't forget the semi-colon!
ctrl-d    # exit psql
ctrl-d    # exit postgres account
```

Create the database: RAILS_ENV=test rake db:create

Configure the database connection in config/database.yml.  The test block should look like:
```
test:
  adapter: postgresql
  encoding: unicode
  database: first_app_test
  pool: 5
  host: localhost
  username: first_app
  password: foobar
```

Start the server: RAILS_ENV=test rails server

When I hit http://192.168.43.5:3000 I get a "no route" message -- which is expected at this point.


TODO: Collapse the above and the scaffolding example into one sequence.

### Creating the microblogging app

The demo application comes directly from www.railstutorial.org/book
I'm not going to spend any time describing it here, as it does quite well for itself.
I'll only comment on the places where I did things differently, or ran into issues.

The first differences I've already mentioned with respect to the scaffolding example, above:
* I want to deploy to a system I've built, not Heroku.
* I want to use postgresql, rather than sqlite, at least beyond the development environment.

To meet these goals, my Gemfile is a little different from that in the book:

```
source 'https://rubygems.org'
ruby '2.0.0'
#ruby-gemset=railstutorial_rails_4_0

gem 'rails', '4.0.8'

group :development do
  gem 'sqlite3', '1.3.8'
end

group :development, :test do
  gem 'rspec-rails', '2.13.1'
end

group :test do
  gem 'selenium-webdriver', '2.35.1'
  gem 'capybara', '2.1.0'
end

gem 'sass-rails', '4.0.1'
gem 'uglifier', '2.1.1'
gem 'coffee-rails', '4.0.1'
gem 'jquery-rails', '3.0.4'
gem 'turbolinks', '1.1.1'
gem 'jbuilder', '1.0.2'

group :doc do
  gem 'sdoc', '0.3.20', require: false
end

group :test, :production do
  gem 'pg', '0.15.1'
end
```

This brings me to the first place where I ran into a snag.

The 'pg' gem has dependencies on postgresql components that I hadn't installed on my development machine.  This led me to run bundler using ```--without production test```, rather than just ```--without production```.  This, in turn, meant that capybara was not installed on my development machine (note the test group in my Gemfile).  So when I came to trying to run my first rspec tests, I ran into two issues, summarized by the following error messages:
Specified 'postgresql' for database adapter, but the gem is not loaded.
spec_helper.rb:43: uninitialized constant Capybara (NameError)

The first problem, I realized, was that spec_helper.rb defaults RAILS_ENV to 'test', which meant that rails was trying to use the 'test' configuration in my database.yml file.  This was easily fixed by running spec with the following command:
```
RAILS_ENV=development bundle exec rspec spec/requests/static_pages_spec.rb
```
But when I did so I received the second message, about Capybara.  Going back to the Gemfile, I realized how my use of different databases in different environments had led to the issue.  I installed postgresql on my development machine and ran ```bundle install --without production```, and finally my tests ran as expected -- which is to say that they failed, but that was expected at this point.  Note that my development database is still configured to be sqlite, but I'll change that at some point in the near future.  Better to keep things as consistent as possible as you move through environments.

With a Jenkins cluster and a minimal application & test suite, I'm just about ready to set up a CI pipeline.  First, though I want to complete my rails infrastructure and automate the provisioning of it.

### Completing the Infrastructure Stack

Above is functioning, but really just in a development capacity.
My production stack will include load balancing (nginx) and an application server (unicorn).
It will also include postgresql, though I started to introduce that, earlier.
In production these will span multiple hosts.  Right now, I'm just going to get everything working on a single node.  It will be easy to split out, later.

Add unicorn gem to Gemfile
bundle update
bundle install
vi config/unicorn.rb
sudo apt-get install nginx
vi /etc/nginx/conf.d/microblog_ruby.conf
sudo service nginx start

### Chef-ifying the Infrastructure

In production, I expect to spread the stack over (at least) three types of node:
* load balancer
* application server
* database server

The provisioning of each will be encapsulated by a chef role.
To collapse the stack onto a single server, I apply all the roles to the same node.
After the infrastructure code is working, I'll create a deploy recipe to take care of the application code.

In each case, there are solid community cookbooks I can leverage.
I'll wrap these using a single cookbook I create, rails_infrastructure:
My roles will reference recipes in rails_infrastructure in their run lists.
Rails environment will derive from chef node environment.

...

After a few iterations, I have my cookbook provisioning everything except the application deployment.  It's [here] with the tag xxxx.  I'll have some refactoring to do, but for now it's good enough.  And once the node is converged, I have only a small set of commands to deploy the application:

```
git clone https://github.com/normseth/microblog_ruby.git
cd microblog_ruby/
bundle install --deployment --without production
bundle exec rake db:migrate
bundle exec unicorn_rails
```

That clone is going against a public repo.  More than likely, I need to work against a private one.
So...

Status:
node setup works ok.
app_deploy cookbook works ok.
caveat: doesn't work if ruby not installed previously (e.g. previous chef-client run)
todo: start application afterwards
possible caveat: when starting manually, need to pass environment RAILS_ENV=test bundle exec....

## Continuously Integrating Infrastructure Code

In the context of my infrastructure code, there are a few different things I want to accomplish:
* On each checkin of infrastructure code, I want to run lint / static analysis tests against it.
* On each checkin of infrastructure code, I want to run unit tests against it.  (Note that I'm implying that failures in lint / static analysis should not block unit tests.)
* On successful completion of unit tests, I want to converge an "integration" node and run integration tests against it.  This node will also be a Jenkins slave, although not the same one as used for application CI.  
The tasks above represent the CI pipeline for my infrastructure code.  Following successful completion, I _may_ want to deploy application code to it and run integration tests for the application, but I'm going to consider that part of the application's CI pipeline, and deal with it later.

Tests Structure
Directory called 'test'  # Default for T-K and can't find where to change, whereas rspec pass path
Tests with cookbook  # some desire to have above (multiple cookbooks) but anticipate would fall under a single cookbook, eventually, in any case (role).  May have to revisit/refactor.

### Lint / Static Analysis
I don't need a converged node on which to run static code analysis tools, but I do need those tools installed on my Jenkins slave.  

Add them as chef gems to slave-ruby recipe.

Add a deploy key for the rails_infrastructure repository, and create a user in Jenkins.  The command to create the key is similar to:
```
ssh-keygen -t rsa -C "devops@level11.com"
```

Put this into the same data bag as our other credential.
```
cat ~/.ssh/jenkins-ci | sed s/$/\\\\n/ | tr -d '\n'
```
Update that data bag.
```
knife data_bag from file creds git_creds.json
```
This is going to spur me create an environment for my CI infrastructure -- probably a good thing, but not something that I'd bothered with, previously.  
Create the file and then the environment.
Put the existing VMs into the environment with
```
knife exec -E 'nodes.transform("name:build*") { |n| n.chef_environment("ci") }'
```
Add resource to build-master recipe to create credential based on the key.  Converge the master.

Looking down the road, I can see I'm going to want to the data bags elsewhere within my CI environment.  I've previously ignored them with .gitignore -- I don't want the files showing up in GitHib.  But now I'm going to write them back to the filesystem in their encrypted, JSON-formatted form.  These files I can then treat as "normal" data bags.
Comment out --secret-file directive from knife.rb
knife data bag show... -Fj > file
Check files into git.

...

Create a slave node (scratch) and a job (rails_infrastructure_foodcritic) using the Jenkins UI.

Run the job, see the results.  Fix them, re-run the job.

References for this section:
http://acrmp.github.io/foodcritic/#ci

### Unit Tests

Unit testing Chef code relies on ChefSpec.
Ref for chef_gem problem (seen with chef-sugar) https://github.com/sethvargo/chefspec/issues/336
Common examples after setting up show something like 'rspec apache' where apache is the name of the cookbook.  This catches all spec tests in the cookbook, which is a problem (I don't want to run my integration tests right now).  Pass the name of the subdirectory you want, as in: 'rspec spec apache/spec/unit'
Also, if using berkshelf for cookbook dependencies, require chefspec/berkshelf in your spec_helper.rb file.

#### Do I need to unit test my third-party code?
### Integration Tests

For integration testing, I'm going to write tests in ServerSpec and drive them using Test-Kitchen.
As I described earlier, these tests will be executed from a Jenkins slave against a full-stack server for my rails infrastructure.  
Add chef_gems for integration testing to build-master::slave-ruby recipe, similar to how I added static/lint earlier.

#### Job Workflow for Integration Tests

x Start with last successfully unit-tested rails_infrastructure code and ci-chef-repo.
x Need either a deploy key or an SSH key.  For moment just copied my key into buildslave & chmod 400.  When running as Jenkins job will get the credential from the job.
x Put encrypted data bag key into ci-chef-repo.
x Put Vagrant insecure private key (also chmod 400) into slave-ruby and converge
x Pull code to slave.
x git clone git@github.com:normseth/rails_infrastructure.git
x Pull chef-repo files to slave.
x git clone git@github.com:normseth/ci-chef-repo.git chef-repo
x Stubbed pem client and validator files and knife config for chef-zero here.  Had to force it into git, since by default I'm ignoring .pem files.
x Get knife.rb into path by hook or crook  # Doing this by checking rails_inf into subdirectory
o Copied .ssh/config  # think this is optional.  skipping....
x and insecure_private_key to buildslave   # added to slave-ruby with data bag
NOTE: os_creds.json should not be included in ci-chef-repo
x Change chef_server_url  # environment variable injected into job with jenkins plugin
cd rails_infrastructure
Pull cookbook dependencies with Berkshelf.  # Could do this earlier & vendor them
x PATH=/opt/chef/embedded/bin:$PATH berks vendor ../../berks-cookbooks   # should vendor this ; path now in job env # berks vendor won't write to an already existing directory
x PATH=/opt/chef/embedded/bin:$PATH berks upload   # copy into cookbooks and use knife serve in job
x # Requires berkshelf be on slave, so add to slave-ruby recipe.  Note that in order to get this to build on the VM, I then had to raise memory to 2048 and CPUs to 2.  Otherwise, it swapped and timed out on the build.
x Launch and populate chef-zero (or knife solo prep)   # using knife serve in job

    cd cookbooks/rails_infrastructure
    berks vendor ../../berks-cookbooks
    cd ../..
    cp -r berks-cookbooks/* cookbooks
    knife serve --chef-repo-path . --chef-zero-host $CHEF_SERVER_IP --chef-zero-port 8889 --repo-mode static &


Or alternative to the above, using test kitchen:



o Launch container/VM    # pre-launched, initially



Converge container/VM (knife solo cook or bootstrapping to chef-zero)
Run tests

STATUS: Unsure whether to use test-kitchen with zero or client provisioner.  If zero, some of the above is moot, since don't need to run knife serve.
TODO: Get the above working, through integration tests, in as repeatable a fashion as possible, using local VMs and EC2.  Document both paths.



```
knife bootstrap 192.168.43.6 -x vagrant -P vagrant --sudo --run-list 'recipe[rails_infrastructure]' --environment 'test' --secret-file /home/vagrant/chef-repo/.chef/insecure_data_bag_secret
```
Rake spec tests against vm/container

And I can execute tests against it from the slave node:
```
/usr/local/rvm/bin/rvm-shell 2.0.0
PATH=/opt/chef/embedded/bin:$PATH rake spec
```

Now drive the same with Test Kitchen.
Re-bootstrap scratch node from my laptop (for now).
Run kitchen init in chef-repo.  
Edit .kitchen.yml to be as follows:

```
---
driver:
  name: vagrant

provisioner:
  name: chef_zero
  # Don't do the . paths, below; fakes out chef-zero
  #data_bags_path: .
  encrypted_data_bag_secret_key_path: ./.chef/insecure_encrypted_data_bag_secret
  #environments_path: .
  require_chef_omnibus: true

platforms:
  - name: ubuntu-12.04
    driver:
      box: opscode-ubuntu-12.04
      box_url: https://opscode-vm-bento.s3.amazonaws.com/vagrant/opscode_ubuntu-12.04_provisionerless.box
      network:
        - ["private_network", {ip: "192.168.43.6"}]
suites:
  - name: default
    run_list: recipe[rails_infrastructure]
    provisioner:
      client_rb:
        environment: test
    attributes:
```

Environments & roles have to be defined as JSON.  Previously have had them as .rb, so convert.
Tests default to a particular location & naming scheme; configurable but not sure how.  
Resolve for the moment by rearranging a little in my cookbook, and symlinking from chef-repo.
kitchen create/converge/verify/destroy/test now work.

Sidebar: I've enabled SSH into my laptop, which means that I can now launch a vagrant VM from a vagrant VM.
ssh -i ~/.ssh/id_rsa normseth@192.168.43.1 "cd demo-v2/vagrant ; vagrant up scratch"


### AWS Cloudformation

aws cloudformation create-stack --stack-name ci-demo --template-body file:///Users/normseth/demo-v2/cfn_templates/VPCSingleSubnet.template --tags Key="owner",Value="nik"

This is a really poor error message.  It may point to an invalid security group name:
Message: InvalidParameterCombination => The parameter groupName cannot be used with the parameter subnet

Had problem getting test kitchen to launch VM with a public ip, even though had flag explicitly set to true.

Tried not setting at all -- no good.
Tried ubuntu 1204 instead of 1404 -- no good.
Found subnet setting EC2 console to add by default.
Looked for same in CFN but no property that seems to apply.
Enabled via console and works -- very poor form, this.


### Using Docker for Integration Tests

This is an experiment, and one of the first things I've learned is that it will be easier with Ubuntu 14.04 than 12.04.  So, I've defined a new node in Vagrantfile and am proceeding with it.
Vagrant up the node
Bootstrap the node with run-list build-master::slave-ruby and environment ci
Set attribute so build-essential installs during compile phase.
Add resources to slave-ruby to install docker.  Wrap these in test for Ubuntu 14.04.
Pull an ubuntu 12.04 docker image.
Run the image, apt-get update, install curl, install chef.
Commit the image.
```
docker pull ubuntu:12.04
docker run -t -i ubuntu:12.04 /bin/bash
# apt-get & curl commands within container...
docker commit -m "installed omnibus chef" -a "Nik Ormseth" 0295e5cd96c2 ubuntu:12.04_chef
docker run -t -i ubuntu:12.04_chef /bin/bash
```
This experiment starts to get a little murky now.
My goal is a container that I can launch, provision, test, and destroy from within my CI pipeline.
Tests are remote, which is to say that they either treat the provisioned node as a black box, or they need to execute in a shell within the node.  But docker containers don't run SSH by default, and doing so just for this purpose seems a little wrong.  The nsenter utility might provide a solution, but I'm not sure how to integrate it with ServerSpec.  Going to set this aside for now.
Some useful reading for when I pick it back up:
* http://jpetazzo.github.io/2014/06/23/docker-ssh-considered-evil/
* https://github.com/jpetazzo/nsenter
* http://www.tommyblue.it/
* http://docs.getchef.com/containers.html
* https://www.youtube.com/watch?v=oj7cdZITpds (slides for this are also on slideshare)
* http://docs.getchef.com/config_yml_kitchen.html
* https://rubygems.org/search?utf8=%E2%9C%93&amp;query=kitchen-

Docker and Test Kitchen (?!)
Tried this out as an alternate path to the above.
Kitchen runs sshd on the container (ok, but I can do that).
Current "full stack" recipe breaks down at the interfaces/ip selection.
Note that this will also probably happen with anyhing other than Vagrant, so basically need to fix it now.

### Setting Up ServerSpec
Create spec directory
Create Rakefile, serverspec_properties.yml and spec/spec_helper.rb per the Advanced instructions on ServerSpec.org.
Want to keep integration and unit tests separate, so create a spec/integration directory, and then make role-specific subdirectories there.
Have set up spec_helper.rb to execute tests via SSH.  This creates a dependency on some sort of credential, which I'll probably manage with an ssh_config and data bag.  

### Writing Tests

I want to validate the post-convergence state of the node.
This implies looking at the node as both a black and a white box.
I expect my test suite will grow over time, as I discover new and interesting ways to screw things up.  But initially, I just want tests that sanity-check each resource in my recipes.

My database tests, for example:
* Does the postgres OS user exist?
* Are client and server packages installed?
* Is the pg gem installed?
* Is postgresql listening on the expected port?
* Does the application database exist?
* Does the application database user exis?

### Tagging Builds

TODO: I want to tag releases that build successfully, but having problem with that in Jenkins with git plugin and multiple SCMs.  Probably user error, but don't want to hang up on it any longer right now.  

## Continuously Integrating Application Code

My demo application only comes with integration tests.
<implement/describe>
Unit tests are a good practice.


## Multi-Node Tests
Kitchen isn't going to work for this...
