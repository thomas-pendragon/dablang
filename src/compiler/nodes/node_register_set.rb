require_relative 'node.rb'
require_relative '../concerns/register_setter_concern.rb'

class DabNodeRegisterSet < DabNode
  include RegisterSetterConcern

  attr_accessor :output_register
  attr_accessor :output_varname

  def initialize(value, output_register, output_varname = nil)
    super()
    insert(value)
    @output_register = output_register
    @output_varname = output_varname
  end

  def value
    @children[0]
  end

  def extra_dump
    "$R#{output_register}= [#{output_varname}]"
  end

  def compile(output)
    if value.respond_to?(:compile_as_ssa)
      value.compile_as_ssa(output, output_register)
    else
      value.compile(output)
      output.print('Q_SET_POP', "R#{output_register}")
    end
  end
end
