require_relative 'node.rb'

class DabNodeSSAPhi < DabNode
  attr_accessor :input_registers
  attr_accessor :input_varname

  def initialize(input_registers, input_varname = nil)
    super()
    @input_registers = input_registers
    @input_varname = input_varname
  end

  def extra_dump
    "R{#{input_registers.join(', ')}} [#{input_varname}]"
  end
end
