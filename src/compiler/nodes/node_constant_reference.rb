require_relative 'node.rb'
require_relative '../processors/strip_unused_value.rb'

class DabNodeConstantReference < DabNode
  attr_reader :target

  lower_with StripUnusedValue

  def initialize(target)
    super()
    @target = target
  end

  def index
    target.index
  end

  def extra_dump
    "$$#{index} [#{target.extra_value}]"
  end

  def extra_value
    target.extra_value
  end

  def real_value
    target.real_value
  end

  def compile(output)
    output.push(self)
  end

  def my_type
    target.my_type
  end

  def constant?
    target.constant?
  end
end
