require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNodeWhile, while: true do
  it 'flattens' do
    node1 = DabNodeSymbol.new(:node1)
    node2 = DabNodeSymbol.new(:node2)
    node3 = DabNodeSymbol.new(:node3)
    node4 = DabNodeSymbol.new(:node4)
    node5 = DabNodeSymbol.new(:node5)

    node_block = DabNodeCodeBlock.new
    node_block << node3
    node_block << node4

    node_while = DabNodeWhile.new(node2, node_block)

    program = DabNodeCodeBlock.new

    program << node1
    program << node_while
    program << node5

    _superparent = DabNodeFunction.new('foo', program, nil, nil)

    result = FlattenWhile.new.run(node_while)
    expect(result).to eq true
  end
end
