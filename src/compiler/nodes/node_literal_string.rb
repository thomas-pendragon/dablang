require_relative 'node_extractable_literal'

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

  def compile_string(output)
    output.print("W_STRING \"#{string}\"")
  end

  def asm_length
    string.length + 1
  end

  def extra_value
    extra_dump
  end

  def my_type
    DabConcreteType.new(DabTypeString.new)
  end

  def formatted_source(_options)
    "\"#{string.gsub("\n", '\\n')}\""
  end

  def constant_value
    @string
  end
end
