name 'integration'
description 'rails stack in a single machine, plus jenkins slave requirements'
run_list 'recipe[build-master::slave-ruby]','recipe[rails_infrastructure::default]'
