require_relative 'node'

class DabNodeSSAPhi < DabNode
  attr_accessor :input_varname

  def initialize(input_registers, input_varname = nil)
    super()
    @input_registers = input_registers
    @input_varname = input_varname
    input_registers.each do |reg|
      insert(DabNodeSSAGet.new(reg))
    end
  end

  def input_registers
    @children.map(&:input_register)
  end

  def extra_dump
    "[#{input_varname}]"
  end

  def formatted_source(_options)
    '__phi(' + input_registers.map { |reg| "SR#{reg}" }.join(', ') + ')'
  end
end
