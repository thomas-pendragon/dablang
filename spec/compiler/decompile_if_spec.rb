require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe DecompileIfs, decompile: true do
  xit 'should decompile if' do
    top_block = DabNodeTreeBlock.new

    block0 = DabNodeBasicBlock.new << DabNodeDefineLocalVar.new('R0', DabNodeArg.new(0, nil))
    block1 = DabNodeBasicBlock.new << DabNodeDefineLocalVar.new('R1', DabNodeLiteralNumber.new(1))
    block2 = DabNodeBasicBlock.new << DabNodeDefineLocalVar.new('R2', DabNodeOperator.new(DabNodeLocalVar.new('R0'), DabNodeLocalVar.new('R1'), '=='))
    block4 = DabNodeBasicBlock.new << DabNodeDefineLocalVar.new('R3', DabNodeLiteralString.new('Foo'))
    block7 = DabNodeBasicBlock.new << DabNodeReturn.new(DabNodeLiteralNil.new)
    block3 = DabNodeBasicBlock.new << DabNodeConditionalJump.new(DabNodeLocalVar.new('R2'), block4, block7)
    block5 = DabNodeBasicBlock.new << DabNodeSyscall.new(0, DabNode.new << DabNodeLocalVar.new('R3'))
    block6 = DabNodeBasicBlock.new << DabNodeJump.new(block7)

    top_block << block0
    top_block << block1
    top_block << block2
    top_block << block3
    top_block << block4
    top_block << block5
    top_block << block6
    top_block << block7

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
      '              DabNodeArg [$0]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeDefineLocalVar [<R1> [1]]',
      '              DabNodeLiteralNumber [1]',
      '          DabNodeBasicBlock [2]',
      '            DabNodeDefineLocalVar [<R2> [2]]',
      '              DabNodeOperator []',
      '                DabNodeSymbol [:==]',
      '                DabNodeLocalVar [<R0> [0]]',
      '                DabNodeLocalVar [<R1> [1]]',
      '          DabNodeBasicBlock [3]',
      '            DabNodeConditionalJump [-> true: 4 | false: 7]',
      '              DabNodeLocalVar [<R2> [2]]',
      '          DabNodeBasicBlock [4]',
      '            DabNodeDefineLocalVar [<R3> [3]]',
      '              DabNodeLiteralString ["Foo"]',
      '          DabNodeBasicBlock [5]',
      '            DabNodeSyscall [#0 PRINT]',
      '              DabNodeLocalVar [<R3> [3]]',
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
    DecompileIfs.new.run(fun)

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
      '              DabNodeArg [$0]',
      '            DabNodeDefineLocalVar [<R1> [1]]',
      '              DabNodeLiteralNumber [1]',
      '            DabNodeDefineLocalVar [<R2> [2]]',
      '              DabNodeOperator []',
      '                DabNodeSymbol [:==]',
      '                DabNodeLocalVar [<R0> [0]]',
      '                DabNodeLocalVar [<R1> [1]]',
      '          DabNodeBasicBlock [1]',
      '            DabNodeIf []',
      '              DabNodeLocalVar [<R2> [2]]',
      '              DabNodeTreeBlock []',
      '                DabNodeDefineLocalVar [<R3> [3]]',
      '                  DabNodeLiteralString ["Foo"]',
      '                DabNodeSyscall [#0 PRINT]',
      '                  DabNodeLocalVar [<R3> [3]]',
      '          DabNodeBasicBlock [2]',
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
