require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  it 'sets parent on clear' do
    node1 = DabNodeSymbol.new(:node1)
    node2 = DabNodeSymbol.new(:node2)
    node3 = DabNodeSymbol.new(:node3)
    node4 = DabNodeSymbol.new(:node4)
    node5 = DabNodeSymbol.new(:node5)

    node1 << node2
    node1 << node3
    node2 << node4
    node2 << node5

    expect(node1.root).to eq(node1)
    expect(node2.root).to eq(node1)
    expect(node3.root).to eq(node1)
    expect(node4.root).to eq(node1)
    expect(node5.root).to eq(node1)

    expect(node1.parent).to eq(nil)
    expect(node2.parent).to eq(node1)
    expect(node3.parent).to eq(node1)
    expect(node4.parent).to eq(node2)
    expect(node5.parent).to eq(node2)

    node2.remove!

    expect(node1.root).to eq(node1)
    expect(node2.root).to eq(node2)
    expect(node3.root).to eq(node1)
    expect(node4.root).to eq(node4)
    expect(node5.root).to eq(node5)

    expect(node1.parent).to eq(nil)
    expect(node2.parent).to eq(nil)
    expect(node3.parent).to eq(node1)
    expect(node4.parent).to eq(nil)
    expect(node5.parent).to eq(nil)
  end

  it 'sets parent on dup' do
    node1 = DabNodeSymbol.new(:node1)
    node2 = DabNodeSymbol.new(:node2)
    node3 = DabNodeSymbol.new(:node3)
    node4 = DabNodeSymbol.new(:node4)
    node5 = DabNodeSymbol.new(:node5)

    node1 << node2
    node1 << node3
    node2 << node4
    node2 << node5

    expect(node1.root).to eq(node1)
    expect(node2.root).to eq(node1)
    expect(node3.root).to eq(node1)
    expect(node4.root).to eq(node1)
    expect(node5.root).to eq(node1)

    expect(node1.parent).to eq(nil)
    expect(node2.parent).to eq(node1)
    expect(node3.parent).to eq(node1)
    expect(node4.parent).to eq(node2)
    expect(node5.parent).to eq(node2)

    node6 = node2.dup
    node1 << node6

    expect(node1.root).to eq(node1)
    expect(node2.root).to eq(node1)
    expect(node3.root).to eq(node1)
    expect(node4.root).to eq(node1)
    expect(node5.root).to eq(node1)
    expect(node6.root).to eq(node1)

    expect(node1.parent).to eq(nil)
    expect(node2.parent).to eq(node1)
    expect(node3.parent).to eq(node1)
    expect(node4.parent).to eq(node2)
    expect(node5.parent).to eq(node2)
    expect(node6.parent).to eq(node1)
  end
end
