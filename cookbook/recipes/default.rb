#
# Cookbook Name:: turnstile
# Recipe:: default
#
# Copyright (C) 2017 Rapid7 LLC.
#
# Distributed under terms of the MIT License. All rights not explicitly granted
# in the MIT license are reserved. See the included LICENSE file for more details.
#

node.default['turnstile']['version'] = cookbook_version

group node['turnstile']['group'] do
  system true
end

user node['turnstile']['user'] do
  comment 'turnstile operator'
  system true

  gid node['turnstile']['group']
  home node['turnstile']['paths']['directory']
end

# Fetch and install Turnstile
remote_file 'turnstile' do
  source Turnstile::Helpers.github_download('rapid7', 'turnstile', node['turnstile']['version'])
  path ::File.join(Chef::Config['file_cache_path'], "turnstile-#{node['turnstile']['version']}.deb")

  action :create_if_missing
  backup false
end

version_dir = "#{ node['turnstile']['paths']['directory'] }-#{ node['turnstile']['version'] }"

package 'turnstile' do
  source resources('remote_file[turnstile]').path
  provider Chef::Provider::Package::Dpkg
  version node['turnstile']['version']

  notifies :create, "link[#{node['turnstile']['paths']['directory']}]", :immediately
end

link node['turnstile']['paths']['directory'] do
  to version_dir

  action :nothing
  notifies :restart, 'service[turnstile]' if node['turnstile']['enable']
end

if Chef::VersionConstraint.new("> 14.04").include?(node['platform_version'])
  service_script_path = '/etc/systemd/system/turnstile.service'
  service_script = 'systemd.service.erb'
  service_provider = Chef::Provider::Service::Systemd
else
  service_script_path = '/etc/init/turnstile.conf'
  service_script = 'upstart.conf.erb'
  service_provider = Chef::Provider::Service::Upstart
end

# Set service script
template service_script_path do
  source service_script
  variables(
    :description => 'turnstile configuration service',
    :user => node['turnstile']['user'],
    :executable => node['turnstile']['paths']['executable'],
    :flags => [
      "-c #{node['turnstile']['paths']['configuration']}"
    ]
  )
end

directory 'turnstile-configuration-directory' do
  path ::File.dirname(node['turnstile']['paths']['configuration'])
  mode '0755'

  recursive true
end

template 'turnstile-configuration' do
  path node['turnstile']['paths']['configuration']
  source 'json.erb'

  variables :properties => node['turnstile']['config']

  notifies :restart, 'service[turnstile]' if node['turnstile']['enable']
end

service 'turnstile' do
  action node['turnstile']['enable'] ? [:start, :enable] : [:stop, :disable]
  provider service_provider
end
