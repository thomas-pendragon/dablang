require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe FixShortcircuit, uint8: true do
  xit 'provides a proper evaluation of ||' do
    op = DabNodeOperator.new(:left, :right, :'||')
    print = DabNodeSyscall.new(0, DabNode.new << op)
    tree = DabNodeTreeBlock.new << :pre << print << :post
    root = DabNodeUnit.new
    root.add_function(DabNodeFunction.new('fun1', tree, nil, false))

    FixShortcircuit.new.run(op)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [fun1]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeTreeBlock []',
      '          DabNodeSymbol [:pre]',
      '          DabNodeSSASet [R0= [$temp0] (2 users)]',
      '            DabNodeSymbol [:left]',
      '          DabNodeIf []',
      '            DabNodeSSAGet [R0 [$temp0]]',
      '            DabNodeTreeBlock []',
      '            DabNodeTreeBlock []',
      '              DabNodeSSASet [R1= [$temp0] (1 users)]',
      '                DabNodeSymbol [:right]',
      '          DabNodeSSASet [R2= [$temp0] (1 users)]',
      '            DabNodeSSAPhi [[]]',
      '              DabNodeSSAGet [R0 []]',
      '              DabNodeSSAGet [R1 []]',
      '          DabNodeSyscall [#0 PRINT]',
      '            DabNodeSSAGet [R2 [$temp0]]',
      '          DabNodeSymbol [:post]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:fun1]',
      '  DabNode []',
      '  DabNode []',
    ]
    expect(root.all_nodes.map(&:simple_info)).to eq(array)
  end
end
