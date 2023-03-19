require_relative 'node_literal'

class DabNodeLiteralFloat < DabNodeLiteral
  attr_reader :number
  def initialize(number)
    super()
    @number = number
  end

  def extra_dump
    number.to_s
  end

  def compile_as_ssa(output, output_register)
    output.comment(self.extra_value)
    output.print('LOAD_FLOAT', "R#{output_register}", extra_dump)
  end

  def extra_value
    extra_dump
  end

  def my_type
    DabConcreteType.new(DabTypeFloat.new)
  end

  def formatted_source(_options)
    extra_dump
  end

  def constant_value
    @number
  end
end
