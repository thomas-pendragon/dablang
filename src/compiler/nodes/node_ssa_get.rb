require_relative 'node.rb'

class DabNodeSSAGet < DabNode
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
    output.print('PUSH_SSA', input_register)
  end
end
