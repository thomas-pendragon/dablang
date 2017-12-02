require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  # - DabNodeUnit (Object) ?:-1
  #   - functions: DabNode (Object) ?:-1
  #     - DabNodeFunction tree1 [flat] (Object) ?:-1
  #       - arglist: DabNode (Object) ?:-1
  #       - blocks: DabNodeBlockNode (Object) ?:-1
  #         - DabNodeSymbol :top (Symbol) ?:-1
  #           - DabNodeSymbol :left (Symbol) ?:-1
  #             - DabNodeSymbol :l1 (Symbol) ?:-1
  #               - DabNodeSymbol :subl1 (Symbol) ?:-1
  #             - DabNodeSymbol :l2 (Symbol) ?:-1
  #             - DabNodeSymbol :l3 (Symbol) ?:-1
  #           - DabNodeSymbol :right (Symbol) ?:-1
  #             - DabNodeSymbol :r1 (Symbol) ?:-1
  #             - DabNodeSymbol :r2 (Symbol) ?:-1
  #             - DabNodeSymbol :r3 (Symbol) ?:-1
  #               - DabNodeSymbol :subr3 (Symbol) ?:-1
  #     - DabNodeFunction tree2 [flat] (Object) ?:-1
  #       - arglist: DabNode (Object) ?:-1
  #       - blocks: DabNodeBlockNode (Object) ?:-1
  #         - DabNodeSymbol :f2 (Symbol) ?:-1
  #           - DabNodeSymbol :f2_1 (Symbol) ?:-1
  #           - DabNodeSymbol :f2_2 (Symbol) ?:-1
  #           - DabNodeSymbol :f2_3 (Symbol) ?:-1
  #   - constants: DabNode (Object) ?:-1
  #   - classes: DabNode (Object) ?:-1

  before do
    @top = DabNodeSymbol.new(:top)
    @left = DabNodeSymbol.new(:left)
    @right = DabNodeSymbol.new(:right)
    @top << @left
    @top << @right
    @l1 = DabNodeSymbol.new(:l1)
    @l2 = DabNodeSymbol.new(:l2)
    @l3 = DabNodeSymbol.new(:l3)
    @r1 = DabNodeSymbol.new(:r1)
    @r2 = DabNodeSymbol.new(:r2)
    @r3 = DabNodeSymbol.new(:r3)
    @left << @l1 << @l2 << @l3
    @right << @r1 << @r2 << @r3
    @subl1 = DabNodeSymbol.new(:subl1)
    @subr3 = DabNodeSymbol.new(:subr3)
    @l1 << @subl1
    @r3 << @subr3

    @f2 = DabNodeSymbol.new(:f2)
    @f2 << DabNodeSymbol.new(:f2_1)
    @f2 << DabNodeSymbol.new(:f2_2)
    @f2 << DabNodeSymbol.new(:f2_3)

    @root = DabNodeUnit.new
    @root.add_function(DabNodeFunction.new('tree1', @top, nil, false))
    @root.add_function(DabNodeFunction.new('tree2', @f2, nil, false))
  end

  it 'list previous nodes 1' do
    expect(@left.previous_nodes(DabNode).map(&:symbol)).to eq %w[top]
  end

  it 'lists previous nodes 2' do
    expect(@l2.previous_nodes(DabNode).map(&:symbol)).to eq %w[top left l1 subl1]
  end

  it 'list following nodes 1' do
    expect(@l2.following_nodes(DabNode).map(&:symbol)).to eq %w[l3]
  end

  it 'list following nodes 1 unscoped' do
    expect(@l2.following_nodes(DabNode, unscoped: true).map(&:symbol)).to eq %w[l3 right r1 r2 r3 subr3]
  end
end
