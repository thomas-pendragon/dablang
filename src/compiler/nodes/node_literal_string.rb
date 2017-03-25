require_relative 'node_literal.rb'

class DabNodeLiteralString < DabNodeLiteral
  attr_reader :string
  def initialize(string)
    super()
    @string = string
  end

  def extra_dump
    "\"#{string}\""
  end

  def compile_constant(output)
    output.print('CONSTANT_STRING', extra_dump)
  end

  def compile(output)
    compile_constant(output)
  end

  def extra_value
    extra_dump
  end

  def my_type
    DabTypeLiteralString.new
  end

  def formatted_source(_options)
    '"' + string.gsub("\n", '\\n') + '"'
  end

  def constant_value
    @string
  end
end
