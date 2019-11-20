#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper.rb'
require_relative '../../ruby_plugin_helper/lib/plugin_helper.rb'
require 'json'
require 'aws-sdk-ec2'

class AwsInventory < TaskHelper
  include RubyPluginHelper

  attr_accessor :client

  def config_client(opts)
    return client if client

    options = {}

    if opts.key?(:region)
      options[:region] = opts[:region]
    end
    if opts.key?(:profile)
      options[:profile] = opts[:profile]
    end
    if opts[:credentials]
      creds = File.expand_path(opts[:credentials], opts[:_boltdir])
      if File.exist?(creds)
        options[:credentials] = Aws::SharedCredentials.new(path: creds)
      else
        msg = "Cannot load credentials file #{creds}"
        raise TaskHelper::Error.new(msg, 'bolt-plugin/validation-error')
      end
    end

    Aws::EC2::Client.new(options)
  end

  def resolve_reference(opts)
    template = opts.delete(:target_mapping) || {}
    unless template.key?(:uri) || template.key?(:name)
      msg = "You must provide a 'name' or 'uri' in 'target_mapping' for the AWS plugin"
      raise TaskHelper::Error.new(msg, 'bolt-plugin/validation-error')
    end

    client = config_client(opts)
    resource = Aws::EC2::Resource.new(client: client)

    # Retrieve a list of EC2 instances and create a list of targets
    # Note: It doesn't seem possible to filter stubbed responses...
    targets = resource.instances(filters: opts[:filters]).select { |i| i.state.name == 'running' }

    attributes = required_data(template)
    target_data = targets.map do |target|
      attributes.each_with_object({}) do |attr, acc|
        attr = attr.first
        acc[attr] = target.respond_to?(attr) ? target.send(attr) : nil
      end
    end

    apply_mapping(template, target_data)
  end

  def task(opts = {})
    targets = resolve_reference(opts)
    { value: targets }
  end
end

AwsInventory.run if $PROGRAM_NAME == __FILE__
