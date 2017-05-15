require_relative 'node_literal.rb'

class DabNodeLiteralNil < DabNodeLiteral
  def compile(output)
    output.print('PUSH_NIL')
  end

  def my_type
    DabTypeNil.new
  end

  def constant_value
    nil
  end
end
