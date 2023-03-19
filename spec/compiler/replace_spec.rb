require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe DabNode do
  it 'allows to replace child' do
    body = DabNodeTreeBlock.new
    p1 = DabNodeSymbol.new(:p1)
    p2 = DabNodeSymbol.new(:p2)
    p3 = DabNodeSymbol.new(:p3)
    body << p1 << p2
    body.replace_child(p2, p3)
    expect(body.all_nodes(DabNodeSymbol).map(&:symbol)).to eq(%w[p1 p3])
  end

  it 'allows to replace child with array' do
    body = DabNodeTreeBlock.new
    p1 = DabNodeSymbol.new(:p1)
    p2 = DabNodeSymbol.new(:p2)
    p3 = DabNodeSymbol.new(:p3)
    p4 = DabNodeSymbol.new(:p4)
    p5 = DabNodeSymbol.new(:p5)
    body << p1 << p2 << p5
    body.replace_child(p2, [p3, p4])
    expect(body.all_nodes(DabNodeSymbol).map(&:symbol)).to eq(%w[p1 p3 p4 p5])
  end

  it 'allows to replace child with array with the child itself' do
    body = DabNodeTreeBlock.new
    p1 = DabNodeSymbol.new(:p1)
    p2 = DabNodeSymbol.new(:p2)
    p3 = DabNodeSymbol.new(:p3)
    p4 = DabNodeSymbol.new(:p4)
    body << p1 << p2 << p4
    body.replace_child(p2, [p2, p3])
    expect(body.all_nodes(DabNodeSymbol).map(&:symbol)).to eq(%w[p1 p2 p3 p4])
  end
end
