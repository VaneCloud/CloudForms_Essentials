=begin
 ec2_create_keypair.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method creates an AWS keypair
-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kevin@redhat.com>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-------------------------------------------------------------------------------
=end
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def get_provider(provider_id=nil)
  $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  provider = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).find_by_id(provider_id)
  log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider

  # set to true to default to the fist amazon provider
  use_default = true
  unless provider
    # default the provider to first openstack provider
    provider = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).first if use_default
    log(:info, "Found amazon: #{provider.name} via default method") if provider && use_default
  end
  provider ? (return provider) : (return nil)
end

def set_service_custom_variables(hash)
  hash.each do |k,v|
    next if v.kind_of?(Array) || v.kind_of?(Hash)
    @service.custom_set(k, v.to_s)
  end
  @service.custom_set('Last Refresh', Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC'))
end

def get_aws_client(type='EC2')
  require 'aws-sdk'
  AWS.config(
    :access_key_id => @provider.authentication_userid,
    :secret_access_key => @provider.authentication_password,
    :region => @provider.provider_region
  )
  return Object::const_get("AWS").const_get("#{type}").new()
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    @task = $evm.root['service_template_provision_task']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @service = @task.destination
    log(:info,"Service: #{@service.name} Id: #{@service.id}")
    @provider = get_provider
  when 'service'
    @service = $evm.root['service']
    log(:info,"Service: #{@service.name} Id: #{@service.id}")
    provider_id   = @service.custom_get(:provider_id)
    @provider ||= get_provider(provider_id)
  else
    exit MIQ_OK
  end

  ec2 = get_aws_client()
  log(:info, "EC2 Client: #{ec2.inspect}")

  keypair_name = "keypair-#{Time.now.to_i}"

  keypair = ec2.key_pairs.create(keypair_name)
  log(:info, "Created Keypair: #{keypair.inspect}")

  if @task
    @task.set_option(:aws_private_key, "#{keypair.private_key}")
    @task.set_option(:aws_keypair, keypair_name)
  end

  @service.custom_set("KEYPAIR_NAME", keypair_name)

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
