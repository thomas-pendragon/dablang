require_relative 'node_extractable_literal.rb'

class DabNodeLiteralString < DabNodeExtractableLiteral
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

  def extra_value
    extra_dump
  end

  def my_type
    DabConcreteType.new(DabTypeString.new)
  end

  def formatted_source(_options)
    '"' + string.gsub("\n", '\\n') + '"'
  end

  def constant_value
    @string
  end

  def compile(output)
    output.print('PUSH_STRING', extra_value)
  end
end
