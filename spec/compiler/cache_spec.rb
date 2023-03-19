require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe DabNode, cache: true do
  it 'rebuilds cache' do
    node1 = DabNodeSymbol.new(:node1)
    expect(node1.all_nodes).to eq([node1])
    node2 = DabNodeSymbol.new(:node2)
    node1 << node2
    expect(node1.all_nodes).to eq([node1, node2])
    copy = node1.dup
    node1.clear
    expect(node1.all_nodes).to eq([node1])
    expect(copy.count).to eq(1)
    expect(copy.all_nodes.count).to eq(2)
  end

  it 'rebuilds parent cache' do
    node1 = DabNodeSymbol.new(:node1)
    node2 = DabNodeSymbol.new(:node2)
    node3 = DabNodeSymbol.new(:node3)

    node1 << node2
    node2 << node3

    expect(node3.all_nodes).to eq([node3])
    expect(node2.all_nodes).to eq([node2, node3])
    expect(node1.all_nodes).to eq([node1, node2, node3])
  end
end
