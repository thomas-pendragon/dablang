require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNodeCallBlock do
  before :each do
    tree = DabNodeTreeBlock.new
    @outer_var = outer_var = DabNodeDefineLocalVar.new('outer', DabNodeLiteralNumber.new(123))
    tree << outer_var
    block_body = DabNodeTreeBlock.new
    block_arg = DabNodeArgDefinition.new(0, 'blockarg', nil, nil)
    @block = block = DabNodeCallBlock.new(block_body, DabNode.new << block_arg)
    @call = DabNodeCall.new('foo', DabNode.new, block)
    tree << @call

    inner_var = DabNodeDefineLocalVar.new('inner', DabNodeLiteralNumber.new(456))
    block_body << inner_var

    arg1 = DabNodeLocalVar.new('outer')
    arg2 = DabNodeLocalVar.new('blockarg')
    arg3 = DabNodeLocalVar.new('inner')
    block_body << DabNodeCall.new('bar', DabNode.new << arg1 << arg2 << arg3, nil)

    @root = root = DabNodeUnit.new
    root.add_function(DabNodeFunction.new('test', tree, nil, false))
  end

  it 'captures outer variables in block' do
    expect(@block.captured_variables).to eq [@outer_var]
  end

  # it 'adds captured variables as extra arguments' do
  #  ExtractCallBlock.new.run(@call)
  #  @root.dump
  # end
end
