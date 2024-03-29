require_relative 'node_extractable_literal'

class DabNodeSymbol < DabNodeExtractableLiteral
  attr_reader :symbol
  attr_accessor :source_ring
  attr_accessor :source_ring_index

  def initialize(symbol)
    raise "empty symbol (#{symbol})" if symbol.to_s.empty?

    super()
    @symbol = symbol.to_stringy
    add_source_parts(symbol)
  end

  def extra_dump
    ret = ":#{symbol}"
    ret += " {{#{source_ring}}" if source_ring
    ret
  end

  def extra_value
    symbol
  end

  def escaped_symbol
    if symbol =~ /^[a-z_]+$/i
      symbol
    else
      "\"#{symbol}\""
    end
  end

  def asm_length
    symbol.length + 1
  end

  def compile_string(output)
    output.print("W_STRING \"#{symbol}\"")
  end

  def compile_constant(output)
    output.print('CONSTANT_SYMBOL', escaped_symbol)
  end

  def my_type
    DabTypeSymbol.new
  end

  def formatted_source(_options)
    extra_dump
  end

  def upper_ring?
    !!source_ring
  end
end
