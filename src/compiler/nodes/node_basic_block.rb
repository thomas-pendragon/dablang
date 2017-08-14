require_relative 'node.rb'

class DabNodeBasicBlock < DabNode
  def extra_dump
    block_index.to_s
  end

  def block_index
    parent_index
  end
end
