require_relative 'node_extractable_literal'
require_relative '../modern_string_escapes'

class DabNodeLiteralString < DabNodeExtractableLiteral
  attr_reader :string

  def initialize(string, modern_source: false, force_byte_assembly: false)
    super()
    @string = string
    @modern_source = modern_source
    @force_byte_assembly = force_byte_assembly
  end

  def extra_dump
    "\"#{string}\""
  end

  def compile_constant(output)
    output.print('CONSTANT_STRING', assembly_literal)
  end

  def compile_string(output)
    if byte_assembly?
      string.each_byte { |byte| output.print('W_BYTE', byte) }
      output.print('W_BYTE', 0)
    else
      output.print("W_STRING #{assembly_literal}")
    end
  end

  def asm_length
    string.length + 1
  end

  def extra_value
    extra_dump
  end

  def constant_table_key
    return extra_value unless byte_assembly?

    [extra_value, :modern_byte_assembly]
  end

  def my_type
    DabConcreteType.new(DabTypeString.new)
  end

  def formatted_source(options)
    if options && options[:syntax_profile].equal?(DabSyntaxProfile::MODERN)
      return DabModernStringEscapes.encode(string)
    end

    escaped = string.gsub('"', '\\"').gsub("\r", '\\r').gsub("\n", '\\n')
    "\"#{escaped}\""
  end

  def constant_value
    @string
  end

private

  def safe_modern_assembly?
    @modern_source && string.include?('\\')
  end

  def byte_assembly?
    @force_byte_assembly || safe_modern_assembly?
  end

  def assembly_literal
    escaped = string.gsub('"') { '""' }
    "\"#{escaped}\""
  end
end
