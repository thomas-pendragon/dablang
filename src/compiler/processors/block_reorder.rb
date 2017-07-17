class BlockReorder
  def run(function)
    return unless function.flat?
    blocks = function.blocks
    order = [blocks[0].block_index]
    jump_labels = blocks.flat_map(&:all_jump_labels)
    jump_labels = jump_labels.uniq
    order += jump_labels
    my_order = blocks.map(&:block_index)
    if order != my_order
      blocks.sort_by! do |child|
        order.index(child.block_index)
      end
      return true
    end
    false
  end
end
