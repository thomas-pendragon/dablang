require_relative 'node.rb'

class DabNodeConstantReference < DabNode
  attr_reader :target

  def initialize(target)
    super()
    @target = target
  end

  def index
    target.index
  end

  def symbol_index
    target.symbol_index
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
    output.print('PUSH_CONSTANT', self.symbol_index)
  end

  def compile_as_ssa(output, output_register)
    if $newformat && target.value.is_a?(DabNodeLiteralString)
      output.comment(self.extra_value)
      output.print('Q_SET_STRING', "R#{output_register}", "_DATA + #{target.asm_position}", target.asm_length - 1)
      return
    end
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
