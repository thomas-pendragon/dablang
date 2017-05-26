require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'pathname'
require 'shellwords'
require 'fileutils'
require 'tempfile'
require 'yaml'

class Object
  def safe_instance_variable_get(name)
    instance_variable_defined?(name) ? instance_variable_get(name) : nil
  end
end
