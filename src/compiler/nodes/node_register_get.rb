require_relative 'node.rb'

class DabNodeRegisterGet < DabNode
  attr_accessor :input_register
  attr_accessor :input_varname

  def initialize(input_register, input_varname = nil)
    super()
    @input_register = input_register
    @input_varname = input_varname
  end

  def extra_dump
    "R#{input_register} [#{input_varname}]"
  end

  def compile(output)
    output.print('PUSH_SSA', "R#{input_register}")
  end

  def compile_as_ssa(output, output_register)
    output.print('Q_SET_REG', "R#{output_register}", "R#{input_register}")
  end

  def setters
    function.all_nodes(DabNodeRegisterSet).select { |node| node.output_register == self.input_register }
  end

  def constant?
    return false if setters.count > 1
    setters.first&.constant_value?
  end

  def constant_value
    raise 'no constant value' unless constant?
    setters.first.value.constant_value
  end

  def my_type
    return DabTypeObject.new unless setters.count == 1
    setters.first.value.my_type
  end

  def register?
    true
  end

  def rename(from, to)
    @input_register = to if @input_register == from
  end

  def register_string
    "R#{input_register}"
  end
end
