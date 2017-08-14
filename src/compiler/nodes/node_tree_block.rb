require_relative 'node.rb'
require_relative '../processors/flatten_tree_block.rb'

class DabNodeTreeBlock < DabNode
  def build_from_tree(current_block, blocks)
    each do |node|
      if node.is_a?(DabNodeTreeBlock)
        current_block = node.build_from_tree(current_block, blocks)
      else
        node._set_parent(nil)
        current_block << node
      end
    end
    current_block
  end

  def topmost?
    !parent.is_a?(DabNodeTreeBlock)
  end
end
