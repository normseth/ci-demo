# See http://docs.opscode.com/config_rb_knife.html for more information on knife configuration options

current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "normseth"
client_key               "#{current_dir}/normseth.pem"
validation_client_name   "demo-v2-validator"
validation_key           "#{current_dir}/demo-v2-validator.pem"
if ENV['CHEF_ZERO'] then
  chef_server_url          "http://192.168.43.1:8889"
else
  chef_server_url          "https://api.opscode.com/organizations/demo-v2"
end
cache_type               'BasicFile'
cache_options( :path => "#{ENV['HOME']}/.chef/checksums" )
cookbook_path            ["#{current_dir}/../cookbooks"]

cookbook_copyright      "Level 11"
cookbook_license        "All rights reserved"
cookbook_email          "nikormseth@level11.com"

# Encyption key for data bags
#knife[:secret_file] = "#{current_dir}/encrypted_data_bag_secret"
