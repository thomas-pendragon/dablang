require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe MergeBlocks, decompile: true do
  it 'should merge blocks with simple jumps' do
    top_block = DabNodeFlatBlock.new

    block0 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(0))
    block1 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(1))
    block3 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(3))
    block4 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(4))
    block2 = DabNodeBasicBlock.new << DabNodeJump.new(block4)
    block6 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(6))
    block5 = DabNodeBasicBlock.new << DabNodeJump.new(block6)

    top_block << block0
    top_block << block1
    top_block << block2
    top_block << block3
    top_block << block4
    top_block << block5
    top_block << block6

    root = DabNodeUnit.new
    fun = DabNodeFunction.new('foo', top_block, DabNode.new, false)
    root.add_function(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeFlatBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [0]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [1]',
      '          DabNodeBasicBlock [2]',
      '            DabNodeJump [->4]',
      '          DabNodeBasicBlock [3]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [3]',
      '          DabNodeBasicBlock [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [4]',
      '          DabNodeBasicBlock [5]',
      '            DabNodeJump [->6]',
      '          DabNodeBasicBlock [6]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [6]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    RemoveNextJumps.new.run(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeFlatBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [0]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [1]',
      '          DabNodeBasicBlock [2]',
      '            DabNodeJump [->4]',
      '          DabNodeBasicBlock [3]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [3]',
      '          DabNodeBasicBlock [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [4]',
      '          DabNodeBasicBlock [5]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [6]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    MergeBlocks.new.run(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeFlatBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [1]',
      '            DabNodeJump [->4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [3]',
      '          DabNodeBasicBlock [1]',
      '          DabNodeBasicBlock [2]',
      '          DabNodeBasicBlock [3]',
      '          DabNodeBasicBlock [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [6]',
      '          DabNodeBasicBlock [5]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    RemoveEmptyBlocks.new.run(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeFlatBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [1]',
      '            DabNodeJump [->1]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [3]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [6]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    RemoveUnreachable.new.run(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeFlatBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [1]',
      '            DabNodeJump [->1]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [6]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'should run decompile postprocess' do
    top_block = DabNodeFlatBlock.new

    block0 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(0))
    block1 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(1))
    block3 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(3))
    block4 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(4))
    block2 = DabNodeBasicBlock.new << DabNodeJump.new(block4)
    block6 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(6))
    block5 = DabNodeBasicBlock.new << DabNodeJump.new(block6)

    top_block << block0
    top_block << block1
    top_block << block2
    top_block << block3
    top_block << block4
    top_block << block5
    top_block << block6

    root = DabNodeUnit.new
    fun = DabNodeFunction.new('foo', top_block, DabNode.new, false)
    root.add_function(fun)

    PostprocessDecompiled.new.run(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeFlatBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [0]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [1]',
      '            DabNodeJump [->1]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [4]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [6]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)
  end

  xit 'should merge blocks with conditional jumps' do
    top_block = DabNodeFlatBlock.new

    block0 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(0))
    block1 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(1))
    block3 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(3))
    block4 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(4))
    block6 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(6))

    block5 = DabNodeBasicBlock.new << DabNodeJump.new(block6)
    block2 = DabNodeBasicBlock.new << DabNodeConditionalJump.new(DabNodeLiteralBoolean.new(true), block3, block6)
    block7 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(7))

    top_block << block0
    top_block << block1
    top_block << block2
    top_block << block3
    top_block << block4
    top_block << block5
    top_block << block6
    top_block << block7

    root = DabNodeUnit.new
    fun = DabNodeFunction.new('foo', top_block, DabNode.new, false)
    root.add_function(fun)

    array = [] # ...

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    # MergeBlocks.new.run(fun)
  end
end
