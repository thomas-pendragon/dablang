class AddMissingReturn
  def run(node)
    return if node.blocks.count > 1
    return if node.blocks[0].ends_with?(DabNodeReturn)
    node.blocks[0].insert(DabNodeReturn.new(DabNodeLiteralNil.new))
    true
  end
end
