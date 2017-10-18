require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  it 'prepends the instruction correctly' do
    top_block = DabNodeTreeBlock.new

    on_true = DabNodeTreeBlock.new << DabNodeSymbol.new(:on_true)

    value1 = DabNodeSymbol.new(:a)
    value2 = DabNodeSymbol.new(:b)
    value3 = DabNodeOperator.new(value1, value2, :+)
    value4 = DabNodeSymbol.new(:c)
    condition = DabNodeOperator.new(value3, value4, :+)

    if_node = DabNodeIf.new(condition, on_true, nil)

    top_block << DabNodeSymbol.new(:before) << if_node << DabNodeSymbol.new(:after)

    root = DabNodeUnit.new
    root.add_function(DabNodeFunction.new('fun1', top_block, nil, false))

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [fun1]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeTreeBlock []',
      '          DabNodeSymbol [:before]',
      '          DabNodeIf []',
      '            DabNodeOperator []',
      '              DabNodeSymbol [:+]',
      '              DabNodeOperator []',
      '                DabNodeSymbol [:+]',
      '                DabNodeSymbol [:a]',
      '                DabNodeSymbol [:b]',
      '              DabNodeSymbol [:c]',
      '            DabNodeTreeBlock []',
      '              DabNodeSymbol [:on_true]',
      '          DabNodeSymbol [:after]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)

    Uncomplexify.new.run(condition)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [fun1]',
      '      DabNode []',
      '      DabNodeBlockNode []',
      '        DabNodeTreeBlock []',
      '          DabNodeSymbol [:before]',
      '          DabNodeSSASet [R0= [$temp0] (1 users)]',
      '            DabNodeOperator []',
      '              DabNodeSymbol [:+]',
      '              DabNodeSymbol [:a]',
      '              DabNodeSymbol [:b]',
      '          DabNodeIf []',
      '            DabNodeOperator []',
      '              DabNodeSymbol [:+]',
      '              DabNodeSSAGet [R0 [$temp0]]',
      '              DabNodeSymbol [:c]',
      '            DabNodeTreeBlock []',
      '              DabNodeSymbol [:on_true]',
      '          DabNodeSymbol [:after]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)
  end
end
