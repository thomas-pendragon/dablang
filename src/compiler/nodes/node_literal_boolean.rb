require_relative 'node_literal.rb'

class DabNodeLiteralBoolean < DabNodeLiteral
  attr_reader :boolean
  def initialize(boolean)
    super()
    @boolean = boolean
  end

  def extra_dump
    boolean.to_s
  end

  def compile_constant(output)
    output.print('CONSTANT_BOOLEAN', boolean ? 1 : 0)
  end

  def compile(output)
    compile_constant(output)
  end

  def extra_value
    extra_dump
  end
end
