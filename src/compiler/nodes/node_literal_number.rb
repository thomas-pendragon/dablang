require_relative 'node_extractable_literal.rb'

class DabNodeLiteralNumber < DabNodeExtractableLiteral
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
    output.print('PUSH_NUMBER', extra_dump)
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
end
