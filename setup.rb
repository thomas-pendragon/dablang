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

  def is_any_of?(list)
    list = [list] unless list.is_a? Array
    list.any? { |item| self.is_a?(item) }
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
