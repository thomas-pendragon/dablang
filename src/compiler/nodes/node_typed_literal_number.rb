require_relative 'node_literal.rb'

class DabNodeTypedLiteralNumber < DabNodeLiteral
  attr_reader :number
  def initialize(number, type)
    super()
    @number = number
    @my_type = type
  end

  def extra_dump
    number.to_s
  end

  def compile_as_ssa(output, output_register)
    output.printex(self, "LOAD_#{my_type.type_string.upcase}", "R#{output_register}", extra_value)
  end

  def extra_value
    number.value
  end

  def my_type
    @my_type
  end

  def constant_value
    @number
  end
end
