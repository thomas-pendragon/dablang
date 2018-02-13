class RemoveEmptyBlocks
  def run(node)
    flat = node.blocks[0]

    remove = []
    flat.each do |block|
      remove << block if block.empty?
    end

    remove.each(&:remove!)

    # TODO: return status
  end
end
