require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe DecompileElseIfs, decompile: true do
  xit 'should decompile if+else' do
    top_block = DabNodeTreeBlock.new

    block0 = DabNodeBasicBlock.new << DabNodeDefineLocalVar.new('R0', DabNodeLiteralNumber.new(0))
    block4 = DabNodeBasicBlock.new << DabNodeDefineLocalVar.new('R3', DabNodeLiteralString.new('Foo'))
    block7 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralNumber.new(7))
    block3 = DabNodeBasicBlock.new << DabNodeConditionalJump.new(DabNodeLocalVar.new('R2'), block4, block7)
    block5 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLocalVar.new('R3'))
    block9 = DabNodeBasicBlock.new << DabNodeReturn.new(DabNodeLiteralNil.new)
    block6 = DabNodeBasicBlock.new << DabNodeJump.new(block9)
    block8 = DabNodeBasicBlock.new << DabNodeJump.new(block9)

    top_block << block0
    top_block << block3
    top_block << block4
    top_block << block5
    top_block << block6
    top_block << block7
    top_block << block8
    top_block << block9

    root = DabNodeUnit.new
    arg0 = DabNodeArgDefinition.new(0, 'arg0', nil, nil)
    fun = DabNodeFunction.new('foo', top_block, DabNode.new << arg0, false)
    root.add_function(fun)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '        DabNodeArgDefinition [#0[arg0]]',
      '      DabNodeBlockNode []',
      '        DabNodeTreeBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeDefineLocalVar [<R0> [0]]',
      '              DabNodeLiteralNumber [0]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeConditionalJump [-> true: 2 | false: 5]',
      '              DabNodeLocalVar [<R2> []]',
      '          DabNodeBasicBlock [2]',
      '            DabNodeDefineLocalVar [<R3> [1]]',
      '              DabNodeLiteralString ["Foo"]',
      '          DabNodeBasicBlock [3]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLocalVar [<R3> [1]]',
      '          DabNodeBasicBlock [4]',
      '            DabNodeJump [->7]',
      '          DabNodeBasicBlock [5]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLiteralNumber [7]',
      '          DabNodeBasicBlock [6]',
      '            DabNodeJump [->7]',
      '          DabNodeBasicBlock [7]',
      '            DabNodeReturn []',
      '              DabNodeLiteralNil []',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    PostprocessDecompiled.new.run(fun)
    DecompileElseIfs.new.run(fun)

    post_array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [foo]',
      '      DabNode []',
      '        DabNodeArgDefinition [#0[arg0]]',
      '      DabNodeBlockNode []',
      '        DabNodeTreeBlock []',
      '          DabNodeBasicBlock [0]',
      '            DabNodeDefineLocalVar [<R0> [0]]',
      '              DabNodeLiteralNumber [0]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeIf []',
      '              DabNodeLocalVar [<R2> []]',
      '              DabNodeTreeBlock []',
      '                DabNodeDefineLocalVar [<R3> [1]]',
      '                  DabNodeLiteralString ["Foo"]',
      '                DabNodeSyscall [#0 PRINT]',
      '                  DabNodeLocalVar [<R3> [1]]',
      '              DabNodeTreeBlock []',
      '                DabNodeSyscall [#0 PRINT]',
      '                  DabNodeLiteralNumber [7]',
      '          DabNodeBasicBlock [2]',
      '          DabNodeBasicBlock [3]',
      '            DabNodeReturn []',
      '              DabNodeLiteralNil []',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:foo]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(post_array)
  end
end
