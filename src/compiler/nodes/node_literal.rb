require_relative 'node.rb'

class DabNodeLiteral < DabNode
  def constant?
    true
  end

  def no_side_effects?
    true
  end
end
