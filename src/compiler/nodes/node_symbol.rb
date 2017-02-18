require_relative 'node_literal.rb'

class DabNodeSymbol < DabNodeLiteral
  attr_reader :symbol
  def initialize(symbol)
    super()
    @symbol = symbol
  end

  def extra_dump
    ":#{symbol}"
  end

  def extra_value
    symbol
  end

  def compile_constant(output)
    val = symbol
    val = "\"#{symbol}\"" unless symbol =~ /^[a-z_]+$/i
    output.print('CONSTANT_SYMBOL', val)
  end

  def my_type
    DabTypeSymbol.new
  end
end
