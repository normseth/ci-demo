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

In the context of my infrastructure code -- i.e. automated provisioning via Chef -- I want to test at a few different levels, each time code is checked in:
* lint / static analysis
* unit tests
* integration tests

### Integration Tests

Install serverspec gem ```gem install serverspec```
Create spec directory
Create Rakefile, roles.yml and spec/spec_helper.rb per the Advanced instructions on ServerSpec.org


## Continuously Integrating Application Code

My demo application only comes with integration tests.
<implement/describe>
Unit tests are a good practice.
