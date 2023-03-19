require_relative 'node_literal'

class DabNodeLiteralBoolean < DabNodeLiteral
  attr_reader :boolean
  def initialize(boolean)
    super()
    @boolean = boolean
  end

  def extra_dump
    boolean.to_s
  end

  def compile_as_ssa(output, output_register)
    output.printex(self, "LOAD_#{@boolean ? 'TRUE' : 'FALSE'}", output_register ? "R#{output_register}" : 'RNIL')
  end

  def extra_value
    extra_dump
  end

  def formatted_source(_options)
    extra_dump
  end

  def constant?
    true
  end

  def constant_value
    @boolean
  end
end
