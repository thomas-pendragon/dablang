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

  def compile(output)
    output.print('PUSH_NUMBER', extra_dump)
  end

  def compile_as_ssa(output, output_register)
    output.comment(self.extra_value)
    output.print('Q_SET_NUMBER', "R#{output_register}", extra_dump)
  end

  def extra_value
    extra_dump
  end

  def my_type
    DabTypeLiteralFixnum.new
  end

  def formatted_source(_options)
    extra_dump
  end

  def constant_value
    @number
  end

  def cast_to(target_type)
    value = TypedNumber.new(number, target_type.type_string)
    DabNodeTypedLiteralNumber.new(value, target_type)
  end
end
