require_relative 'node_literal.rb'

class DabNodeLiteralNumber < DabNodeLiteral
  attr_reader :number
  def initialize(number)
    super()
    @number = number
  end

  def extra_dump
    number.to_s
  end

  def compile_constant(output)
    output.print('CONSTANT_NUMBER', extra_dump)
  end

  def compile(output)
    compile_constant(output)
  end

  def extra_value
    extra_dump
  end

  def my_type
    DabTypeFixnum.new
  end
end
