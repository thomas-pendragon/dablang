require_relative 'node.rb'

class DabNodeLiteralNil < DabNode
  def compile(output)
    output.print('PUSH_NIL')
  end

  def constant?
    true
  end

  def my_type
    DabTypeNil.new
  end

  def constant_value
    nil
  end
end
