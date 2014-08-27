name 'integration'
description 'rails stack in a single machine, plus jenkins slave requirements'
run_list 'recipe[build-master::slave-ruby]','recipe[rails_infrastructure::default]'

default_attributes({
  'rvm' => {
    'global_gems' => [
      { 'name'    => 'bundler' },
      { 'name'    => 'rake', 'version' => '10.3.2'},
      { 'name'    => 'foodcritic'},
      { 'name'    => 'serverspec'},
      { 'name'    => 'rubygems-bundler', 'action'  => 'remove' }
    ]
  }
})
