require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe AddLocalvarPostfix do
  before do
    #               | - DabNodeFunction call (Object)
    #               |   - arglist: DabNode (Object)
    # top_block     |   - blocks: DabNodeBlockNode (Object)
    # inner_block   |     - DabNodeTreeBlock (Object)
    # def           |       - DabNodeDefineLocalVar <other> [0] (Object)
    #               |         - DabNodeLiteralString
    # block1        |       - DabNodeTreeBlock (Object)
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
    @block1 = DabNodeTreeBlock.new
    @block2 = DabNodeTreeBlock.new
    @inner_block << @block1 << @block2
    @literal1 = DabNodeLiteralString.new('foo')
    @def = DabNodeDefineLocalVar.new('a', @literal1)
    @top_block << @def
    @top_block << @inner_block
    @use = DabNodeLocalVar.new('a')
    @call = DabNodeCall.new('print', [@use], nil)
    @block2 << @call

    @root = DabNodeUnit.new
    @root.add_function(DabNodeFunction.new('fun1', @top_block, nil, false))

    @root.dump(true)
  end

  it 'should find all users' do
    AddLocalvarPostfix.new.run(@def)
    expect(@def.all_users).to eq [@def, @use]
  end
end
