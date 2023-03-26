class BlockToVariable
  def run(node)
    return false unless node.has_block?

    id = node.function.allocate_tempvar

    node_block = node.block.dup
    node.block.replace_with!(DabNodeLiteralNil.new)

    blockvar = DabNodeVarBlock.new(node_block.body, node_block.arglist)
    define_var = DabNodeDefineLocalVar.new(id, blockvar)
    read_var = DabNodeLocalVar.new(id)
    local_block = DabNodeLocalBlock.new(read_var)

    node.prepend_instruction(define_var)
    node.insert(local_block)

    blockvar.early_init!

    true
  end
end
