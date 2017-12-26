require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'pathname'
require 'shellwords'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'digest'
require 'open3'

if OS.windows?
  STDOUT.sync = true
end

class Object
  def safe_instance_variable_get(name)
    instance_variable_defined?(name) ? instance_variable_get(name) : nil
  end

  def is_any_of?(list)
    return self.is_a?(list) if list.is_a?(Class)
    list.any? { |item| self.is_a?(item) }
  end

  def is_kind_of_any?(list)
    return self.class == list if list.is_a?(Class)
    list.any? { |item| self.class == item }
  end

  def present?
    true
  end
end

class NilClass
  def present?
    false
  end
end

class String
  def present?
    strip != ''
  end
end
