require_relative 'node.rb'
require_relative '../processors/store_locally.rb'

class DabNodeConstantReference < DabNode
  include NodeStoredLocally

  attr_reader :target

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
    output.comment(self.extra_value)
    output.print('PUSH_CONSTANT', self.index)
  end

  def compile_as_ssa(output, output_register)
    output.comment(self.extra_value)
    output.print('Q_SET_CONSTANT', "R#{output_register}", self.index)
  end

  def my_type
    target.my_type
  end

  def constant?
    target.constant?
  end

  def constant_value
    target.constant_value
  end

  def on_added
    super
    target.register_reference(self)
  end

  def on_removed
    super
    target.unregister_reference(self)
  end
end
