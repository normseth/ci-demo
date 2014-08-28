## Getting Started

### CI Infrastructure
Created a project directory.
Initialized git; set exclusions.
Defined build master and slave VMs in Vagrantfile.
Cloned build-master into cookbooks.
Made some changes.  Exact nature not relevant, but process is:
  Launched VM.
  Set environment for chef-zero.
  Ran berks install from role-buildserver to get cookbook dependencies.
  Ran berks upload to push all cookbooks into chef-zero.
  Bootstrapped manually with knife.
  Iterated over my cookbook, forcing the upload with knife as needed (not bumping version).
At the end of the day, I have a two-node Jenkins cluster up & running, although the slave doesn't yet have the Ruby on Rails stack to support my demo application.

TODO: Fix security for Jenkins.  Currently broken, but not blocking.  Issue is that my config-file hack gets over-written somewhere, and is fragile, in any case, because slaves are also configured in the same file.

### Application Environment
I could go straight to the community and find a cookbook to set up my rails stack, but I'm going to take a lower-level approach at first, to ensure I understand the infrastructure.  The gist is that I'm going to manually install the infrastructure on a fresh VM, capturing the steps in my command history file.  At the end, I'll distill it down to just the tasks I need to automate (skipping all digressions & mistakes), and build or borrow recipes to suit.

I'm working from this document: http://www.railstutorial.org/book/beginning#sec-up_and_running

NOTE: This section conflates application code and infrastructure, and doesn't actually cover several components of the infrastructure requirements (nginx, passenger, etc.).

TODO: Address previous note, then address how infrastructure code gets applied to a jenkins slave in a dynamic, automated fashion.  Could be that master is configured with nodes dynamically, or could be that they're booted and provisioned from code, then torn down.

And here's my distilled command history, once I have my first application up & running.  At this point, this is just a development stack (aka group, as defined in first_app/Gemfile):
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
The rails tutorial I'm working from deploys to Heroku, but that's not what I want in this case.
Instead, I want to define a new VM (which may eventually become a cluster of them) that I can build provision with Chef, and deploy to using Chef (or possibly Capistrano).

I'll call this VM 'rtest'.
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


### Lint / Static Analysis
I don't need a converged node on which to run static code analysis tools, but I do need those tools installed on _some_ Jenkins node, and I'm planning to execute them on a slave.  So, I modify my generic slave recipe to be 'slave-ruby' and add RVM installation to it.  Against my 'scratch' VM, bootstrapping now looks like:
```
knife bootstrap 192.168.43.6 -x vagrant -P vagrant --sudo --run-list 'recipe[build-master::slave-ruby]' --environment 'test'
```

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
This is going to spur me create an environment for my CI infrastructure -- not a bad thing, but not something that I'd bothered with, previously.  
Create the file and then the environment.
Put the existing VMs into the environment with
```
knife exec -E 'nodes.transform("name:build*") { |n| n.chef_environment("ci") }'
```
Add resource to master recipe to create credential based on the key.  Converge the master.

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

#### Do I need to unit test my third-party code?
### Integration Tests

For integration testing, I'm going to use ServerSpec.
As I described earlier, these tests will run, post-convergence, on a node that is both a Jenkins slave and a full-stack server for my rails infrastructure.  I use knife to create a role that encapsulates this in its runlist.  The role definition looks like:
```
# chef-repo/roles/integration.rb
name 'integration'
description 'rails stack in a single machine, plus jenkins slave requirements'
run_list 'recipe[build-master::slave-ruby]','recipe[rails_infrastructure::default]'
```

#### Job Workflow for Integration Tests

Start with last successfully unit-tested code.
Need either a deploy key or an SSH key.  For moment just copied my key into buildslave.
Did same for encrypted data bag key
Pull code to slave.
Pull chef-repo files to slave. # Stubbed pem client and validator files and knife config for chef-zero here.  Had to force it into git, since by default I'm ignoring .pem files.
Pull cookbook dependencies with Berkshelf.  # Could do this earlier & vendor them
Get knife.rb into path by hook or crook
PATH=/opt/chef/embedded/bin berks install
PATH=/opt/chef/embedded/bin berks upload
Requires berkshelf be on slave, so add to slave-ruby recipe.  Note that in order to get this to build on the VM, I then had to raise memory to 2048 and CPUs to 2.  Otherwise, it swapped and timed out on the build.
Launch and populate chef-zero # Or knife solo prep
Launch and converge container (knife solo cook or bootstrapping to chef-zero)
Rake spec tests against container
Terminate container
Terminate chef-zero (if used)


Add serverspec gem as default to be installed by build-master::slave-ruby.  This is done by adding to attribute hash in build-master attributes file.  Manually, would be ```gem install serverspec```.
Sidebar: The first time I converged a node, I discovered that I had conflicting global gem definitions in the rails_infrastructure and build-master cookbooks.  I decided to resolve these by adding an attribute to my role which correctly defines the set.

Now I can bootstrap the (previously launched) VM:
```
knife bootstrap 192.168.43.6 -x vagrant -P vagrant --sudo --run-list 'role[integration]' --environment 'test'
```

### Setting Up ServerSpec
Create spec directory
Create Rakefile, serverspec_properties.yml and spec/spec_helper.rb per the Advanced instructions on ServerSpec.org.
Want to keep integration and unit tests separate, so create a spec/integration directory, and then make role-specific subdirectories there.
Have set up spec_helper.rb to execute tests via SSH.  This creates a dependency on some sort of credential, which I'll probably manage with an ssh_config and data bag.  

### Writing Tests

## Continuously Integrating Application Code

My demo application only comes with integration tests.
<implement/describe>
Unit tests are a good practice.
