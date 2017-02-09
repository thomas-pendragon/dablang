require_relative 'node.rb'

class DabNodeOperator < DabNode
  def initialize(left, right, method)
    super()
    insert(method.to_sym)
    insert(left)
    insert(right)
  end

  def identifier
    children[0]
  end

  def left
    children[1]
  end

  def right
    children[2]
  end

  def compile(output)
    left.compile(output)
    right.compile(output)
    output.push(identifier)
    output.comment("op #{identifier.extra_value}")
    output.print('CALL', 2, 1)
  end
end
