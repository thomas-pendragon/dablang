require_relative 'node.rb'

class DabNodeSSASet < DabNode
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
    "R#{output_register}= [#{output_varname}]"
  end

  def compile(output)
    raise 'unsupported value' unless value.respond_to?(:compile_as_ssa)
    value.compile_as_ssa(output, output_register)
  end

  def returns_value?
    false
  end
end
