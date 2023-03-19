require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe FlattenTreeBlock do
  it 'flattens simple tree' do
    sa = DabNodeSymbol.new(:a)

    top = DabNodeTreeBlock.new << sa
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(top)

    array = [
      'DabNode []',
      '  DabNodeFlatBlock []',
      '    DabNodeBasicBlock [0]',
      '      DabNodeSymbol [:a]',
    ]

    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'flattens complex tree' do
    sa = DabNodeSymbol.new(:a)
    sb = DabNodeSymbol.new(:b)
    sc = DabNodeSymbol.new(:c)

    inner = DabNodeTreeBlock.new << sb
    top = DabNodeTreeBlock.new << sa << inner << sc
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(top)

    array = [
      'DabNode []',
      '  DabNodeFlatBlock []',
      '    DabNodeBasicBlock [0]',
      '      DabNodeSymbol [:a]',
      '      DabNodeSymbol [:b]',
      '      DabNodeSymbol [:c]',
    ]

    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'flattens tree with if' do
    sa = DabNodeSymbol.new(:a)
    sb = DabNodeSymbol.new(:b)
    sc = DabNodeSymbol.new(:c)
    sd = DabNodeSymbol.new(:d)

    l1 = DabNodeLiteralNumber.new(1)

    nif = DabNodeIf.new(l1, DabNodeTreeBlock.new << sb, DabNodeTreeBlock.new << sc)

    top = DabNodeTreeBlock.new << sa << nif << sd
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(top)

    array = [
      'DabNode []',
      '  DabNodeFlatBlock []',
      '    DabNodeBasicBlock [0]',
      '      DabNodeSymbol [:a]',
      '      DabNodeConditionalJump [-> true: 1 | false: 2]',
      '        DabNodeLiteralNumber [1]',
      '    DabNodeBasicBlock [1]',
      '      DabNodeSymbol [:b]',
      '      DabNodeJump [->3]',
      '    DabNodeBasicBlock [2]',
      '      DabNodeSymbol [:c]',
      '      DabNodeJump [->3]',
      '    DabNodeBasicBlock [3]',
      '      DabNodeSymbol [:d]',
    ]
    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'flattens tree with while' do
    sa = DabNodeSymbol.new(:a)
    sb = DabNodeSymbol.new(:b)
    sc = DabNodeSymbol.new(:c)

    l1 = DabNodeLiteralNumber.new(1)

    nwhile = DabNodeWhile.new(l1, DabNodeTreeBlock.new << sb)

    top = DabNodeTreeBlock.new << sa << nwhile << sc
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(top)

    array = [
      'DabNode []',
      '  DabNodeFlatBlock []',
      '    DabNodeBasicBlock [0]',
      '      DabNodeSymbol [:a]',
      '      DabNodeJump [->1]',
      '    DabNodeBasicBlock [1]',
      '      DabNodeConditionalJump [-> true: 2 | false: 3]',
      '        DabNodeLiteralNumber [1]',
      '    DabNodeBasicBlock [2]',
      '      DabNodeSymbol [:b]',
      '      DabNodeJump [->1]',
      '    DabNodeBasicBlock [3]',
      '      DabNodeSymbol [:c]',
    ]
    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'flattens tree with if/while' do
    sa = DabNodeSymbol.new(:a)
    sb = DabNodeSymbol.new(:b)
    sc = DabNodeSymbol.new(:c)
    sd = DabNodeSymbol.new(:d)
    se = DabNodeSymbol.new(:e)
    sf = DabNodeSymbol.new(:f)

    l1 = DabNodeLiteralNumber.new(1)
    l2 = DabNodeLiteralNumber.new(2)

    nif = DabNodeIf.new(l2, DabNodeTreeBlock.new << sc, DabNodeTreeBlock.new << sd)
    nwhile = DabNodeWhile.new(l1, DabNodeTreeBlock.new << sb << nif << se)

    top = DabNodeTreeBlock.new << sa << nwhile << sf
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(top)

    # ap parent.all_nodes.map(&:simple_info)
    array = [
      'DabNode []',
      '  DabNodeFlatBlock []',
      '    DabNodeBasicBlock [0]',
      '      DabNodeSymbol [:a]',
      '      DabNodeJump [->1]',
      '    DabNodeBasicBlock [1]',
      '      DabNodeConditionalJump [-> true: 2 | false: 6]',
      '        DabNodeLiteralNumber [1]',
      '    DabNodeBasicBlock [2]',
      '      DabNodeSymbol [:b]',
      '      DabNodeConditionalJump [-> true: 3 | false: 4]',
      '        DabNodeLiteralNumber [2]',
      '    DabNodeBasicBlock [3]',
      '      DabNodeSymbol [:c]',
      '      DabNodeJump [->5]',
      '    DabNodeBasicBlock [4]',
      '      DabNodeSymbol [:d]',
      '      DabNodeJump [->5]',
      '    DabNodeBasicBlock [5]',
      '      DabNodeSymbol [:e]',
      '      DabNodeJump [->1]',
      '    DabNodeBasicBlock [6]',
      '      DabNodeSymbol [:f]',
    ]
    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'flattens tree with while/if' do
    sa = DabNodeSymbol.new(:a)
    sb = DabNodeSymbol.new(:b)
    sc = DabNodeSymbol.new(:c)
    sd = DabNodeSymbol.new(:d)
    se = DabNodeSymbol.new(:e)
    sf = DabNodeSymbol.new(:f)

    l1 = DabNodeLiteralNumber.new(1)
    l2 = DabNodeLiteralNumber.new(2)

    nwhile = DabNodeWhile.new(l2, DabNodeTreeBlock.new << sd)
    nif = DabNodeIf.new(l1, DabNodeTreeBlock.new << sb, DabNodeTreeBlock.new << sc << nwhile << se)

    top = DabNodeTreeBlock.new << sa << nif << sf
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(top)

    array = [
      'DabNode []',
      '  DabNodeFlatBlock []',
      '    DabNodeBasicBlock [0]',
      '      DabNodeSymbol [:a]',
      '      DabNodeConditionalJump [-> true: 1 | false: 2]',
      '        DabNodeLiteralNumber [1]',
      '    DabNodeBasicBlock [1]',
      '      DabNodeSymbol [:b]',
      '      DabNodeJump [->6]',
      '    DabNodeBasicBlock [2]',
      '      DabNodeSymbol [:c]',
      '      DabNodeJump [->3]',
      '    DabNodeBasicBlock [3]',
      '      DabNodeConditionalJump [-> true: 4 | false: 5]',
      '        DabNodeLiteralNumber [2]',
      '    DabNodeBasicBlock [4]',
      '      DabNodeSymbol [:d]',
      '      DabNodeJump [->3]',
      '    DabNodeBasicBlock [5]',
      '      DabNodeSymbol [:e]',
      '      DabNodeJump [->6]',
      '    DabNodeBasicBlock [6]',
      '      DabNodeSymbol [:f]',
    ]
    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'should do nothing on non-top block' do
    sa = DabNodeSymbol.new(:a)
    sb = DabNodeSymbol.new(:b)
    sc = DabNodeSymbol.new(:c)

    inner = DabNodeTreeBlock.new << sb
    top = DabNodeTreeBlock.new << sa << inner << sc
    parent = DabNode.new << top

    FlattenTreeBlock.new.run(inner)

    array = [
      'DabNode []',
      '  DabNodeTreeBlock []',
      '    DabNodeSymbol [:a]',
      '    DabNodeTreeBlock []',
      '      DabNodeSymbol [:b]',
      '    DabNodeSymbol [:c]',
    ]

    expect(parent.all_nodes.map(&:simple_info)).to eq(array)
  end
end
