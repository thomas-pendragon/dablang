require_relative 'node.rb'

class DabNodeLiteral < DabNode
  def constant?
    true
  end
end
