require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe AddLocalvarPostfix do
  before do
    #               | - DabNodeFunction call (Object)
    #               |   - arglist: DabNode (Object)
    # top_block     |   - blocks: DabNodeBlockNode (Object)
    # inner_block   |     - DabNodeTreeBlock (Object)
    # block1        |       - DabNodeTreeBlock (Object)
    # def           |         - DabNodeDefineLocalVar <other> [0] (Object)
    #               |           - DabNodeLiteralString
    # block2        |       - DabNodeTreeBlock (Object)
    # call          |         - DabNodeCall [builtin] (Object)
    #               |           - identifier: DabNodeSymbol :print (Symbol)
    #               |           - block: DabNodeLiteralNil (NilClass!)
    #               |           - block_capture: DabNodeLiteralNil (NilClass!)
    # use           |           - DabNodeLocalVar <other> [0] (Object)
    #               |       - DabNodeReturn (Object)
    #               |         - DabNodeLiteralNil (NilClass!)
    #               |   - attrlist: DabNode (Object)
    #               |   - DabNodeLiteralNil (NilClass!)
    #               |   - identifier: DabNodeSymbol :call (Symbol)
    #               |   - arg_symbols: DabNode (Object)

    @top_block = DabNodeTreeBlock.new
    @inner_block = DabNodeTreeBlock.new
    @top_block << @inner_block
    @block1 = DabNodeTreeBlock.new
    @block2 = DabNodeTreeBlock.new
    @inner_block << @block1 << @block2
    @literal1 = DabNodeLiteralString.new('foo')
    @def = DabNodeDefineLocalVar.new('a', @literal1)
    @block1 << @def
    @use = DabNodeLocalVar.new('a')
    @call = DabNodeCall.new('print', [@use], nil)
    @block2 << @call

    @root = DabNodeUnit.new
    @root.add_function(DabNodeFunction.new('fun1', @top_block, nil, false))

    # @root.dump(true)
  end

  # - DabNodeUnit (Object) ?:-1
  #   - functions: DabNode (Object) ?:-1
  #     - DabNodeFunction fun1 (Object) ?:-1
  #       - arglist: DabNode (Object) ?:-1
  #       - blocks: DabNodeBlockNode (Object) ?:-1
  #         - DabNodeTreeBlock (Object) ?:-1
  #           - DabNodeTreeBlock (Object) ?:-1
  #             - DabNodeTreeBlock (Object) ?:-1
  #               - DabNodeDefineLocalVar <a> [0] (Object) ?:-1
  #                 - DabNodeLiteralString "foo" (String!) ?:-1
  #             - DabNodeTreeBlock (Object) ?:-1
  #               - DabNodeCall [builtin] (Object) ?:-1
  #                 - identifier: DabNodeSymbol :print (Symbol) ?:-1
  #                 - block: DabNodeLiteralNil (NilClass!) ?:-1
  #                 - block_capture: DabNodeLiteralNil (NilClass!) ?:-1
  #                 - DabNodeLocalVar <a> [0] (Object) ?:-1
  #       - attrlist: DabNode (Object) ?:-1
  #       - DabNodeLiteralNil (NilClass!) ?:-1
  #       - identifier: DabNodeSymbol :fun1 (Symbol) ?:-1
  #       - arg_symbols: DabNode (Object) ?:-1
  #   - constants: DabNode (Object) ?:-1
  #   - classes: DabNode (Object) ?:-1

  it 'should find all users' do
    AddLocalvarPostfix.new.run(@def)
    expect(@def.all_users).to eq [@def, @use]
  end
end
