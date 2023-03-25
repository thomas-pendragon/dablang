# - block: DabNodeCallBlock (Object) ./tmp/test_asm_spec_0097_blockvar.dab:6
#   - body: DabNodeTreeBlock (Object) ./tmp/test_asm_spec_0097_blockvar.dab:7
#     - DabNodeCall [builtin] (Object) ./tmp/test_asm_spec_0097_blockvar.dab:7
#       - identifier: DabNodeSymbol :print (Symbol) ./tmp/test_asm_spec_0097_blockvar.dab:7
#       - block: DabNodeLiteralNil (NilClass!) ?:-1
#       - block_capture: DabNodeLiteralNil (NilClass!) ?:-1
#       - DabNodeLiteralNumber 2 (Fixnum!) ./tmp/test_asm_spec_0097_blockvar.dab:7
# - DabNodeCall (Object) ./tmp/test_asm_spec_0097_blockvar.dab:6
#   - identifier: DabNodeSymbol :foo (Symbol) ./tmp/test_asm_spec_0097_blockvar.dab:6
#   - block: DabNodeBlockReference (Object) ./tmp/test_asm_spec_0097_blockvar.dab:4
#     - DabNodeSymbol :main__block1 (Symbol) ./tmp/test_asm_spec_0097_blockvar.dab:4
#   - block_capture: DabNodeLiteralNil (NilClass!) ?:-1

class BlockToVariable
  def run(node)
    return false unless node.has_block?

    node.function.dump

    id = node.function.allocate_tempvar

    node_block = node.block.dup
    node.block.replace_with!(DabNodeLiteralNil.new)

    blockvar = DabNodeVarBlock.new(node_block, nil)
    define_var = DabNodeDefineLocalVar.new(id, blockvar)
    read_var = DabNodeLocalVar.new(id)
    local_block = DabNodeLocalBlock.new(read_var)

    node.prepend_in_parent(define_var)
    node.insert(local_block)

    puts '---------------'
    node.function.dump
    # 900        ret.add_source_parts(op, lparen, rparen)
    #   prepend_in_parent

    # reg = node.function.allocate_ssa
    # setter = DabNodeSSASet.new(arg_dup, reg, id)
    # getter = DabNodeSSAGet.new(reg, id)
    raise 'a'
  end
end
