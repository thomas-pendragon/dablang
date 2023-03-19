require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe DabNode do
  it 'optimizes constant if (true)' do
    on_true = DabNodeSymbol.new(:on_true)
    on_false = DabNodeSymbol.new(:on_false)
    condition = DabNodeLiteralBoolean.new(true)
    if_node = DabNodeIf.new(condition, on_true, on_false)
    parent = DabNode.new << if_node
    OptimizeConstantIf.new.run(if_node)
    list = [
      'DabNode',
      'DabNodeSymbol:on_true',
    ]
    expect(parent.all_nodes.map(&:extra_debug_dump)).to eq list
  end

  it 'optimizes constant if (false)' do
    on_true = DabNodeSymbol.new(:on_true)
    on_false = DabNodeSymbol.new(:on_false)
    condition = DabNodeLiteralBoolean.new(false)
    if_node = DabNodeIf.new(condition, on_true, on_false)
    parent = DabNode.new << if_node
    OptimizeConstantIf.new.run(if_node)
    list = [
      'DabNode',
      'DabNodeSymbol:on_false',
    ]
    expect(parent.all_nodes.map(&:extra_debug_dump)).to eq list
  end
end
