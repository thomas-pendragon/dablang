class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    name = node.function.new_block_name

    fun = DabNodeFunction.new(name, block.body, block.arglist, false)

    fun.init!

    node.root.add_function(fun)
    node.block.replace_with!(DabNodeBlockReference.new(fun))

    true
  end
end
