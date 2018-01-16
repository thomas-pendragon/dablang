require_relative 'node.rb'

class DabNodeLiteral < DabNode
  def constant?
    true
  end

  def no_side_effects?
    true
  end

  def upper_ring?
    false
  end

  def source_ring_index
    0
  end
end
