require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  it 'handles correct setter in tree' do
    n_value = DabNodeLiteralNumber.new(1)
    n_value2 = DabNodeLiteralNumber.new(2)
    n_define = DabNodeDefineLocalVar.new('a', n_value)
    n_getter = DabNodeLocalVar.new('a')
    n_call = DabNodeOperator.new(n_getter, n_value2, :+)
    n_setter = DabNodeSetLocalVar.new('a', n_call)
    n_getter2 = DabNodeLocalVar.new('a')
    n_print = DabNodeSyscall.new(0, DabNode.new << n_getter2)
    _top = DabNodeTreeBlock.new << n_define << n_setter << n_print

    expect(n_getter.last_var_setter).to eq(n_define)
    expect(n_getter2.last_var_setter).to eq(n_setter)
  end

  it 'should follow nodes' do
    tree = DabNodeSymbol.new(:t)
    tree1 = DabNodeSymbol.new(:t1)
    tree11 = DabNodeSymbol.new(:t11)
    tree11a = DabNodeSymbol.new(:t11a)
    tree111 = DabNodeSymbol.new(:t111)
    tree2 = DabNodeSymbol.new(:t2)
    tree22 = DabNodeSymbol.new(:t22)
    tree222 = DabNodeSymbol.new(:t222)

    tree << tree1 << tree2
    tree1 << tree11 << tree11a
    tree11 << tree111
    tree2 << tree22
    tree22 << tree222

    symbol1 = DabNodeSymbol.new(:a)
    symbol2 = DabNodeSymbol.new(:b)

    tree111 << symbol1
    tree222 << symbol2

    expect(symbol1.following_nodes(DabNodeSymbol)).to eq []
    expect(symbol1.following_nodes(DabNodeSymbol, unscoped: true)).to eq [tree11a, tree2, tree22, tree222, symbol2]
  end

  it 'ssaifies captured variable' do
    arglist = DabNode.new
    arglist << DabNodeArgDefinition.new(0, 'bar', nil)

    tree = DabNodeTreeBlock.new

    tree << DabNodeDefineLocalVar.new('bar', DabNodeArg.new(0))
    closure_var_def = DabNodeDefineLocalVar.new('other#1', DabNodeClosureVar.new(0))
    tree << (DabNodeTreeBlock.new << closure_var_def)
    var1 = DabNodeLocalVar.new('bar')
    var2 = DabNodeLocalVar.new('other#1')
    call = DabNodeCall.new('qux', (DabNode.new << var1 << var2), nil)
    tree << (DabNodeTreeBlock.new << call)
    tree << DabNodeReturn.new(DabNodeLiteralNil.new)

    root = DabNodeUnit.new
    func = DabNodeFunction.new('test', tree, arglist, false)
    root.add_function(func)

    expect(closure_var_def.all_unscoped_users).to eq [closure_var_def, var2]

    SSAify.new.run(func)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [test]',
      '      DabNode []',
      '        DabNodeArgDefinition [#0[bar]]',
      '      DabNodeBlockNode []',
      '        DabNodeTreeBlock []',
      '          DabNodeSSASet [R0= [bar] (1 users)]',
      '            DabNodeArg [$0]',
      '          DabNodeTreeBlock []',
      '            DabNodeSSASet [R1= [other#1] (1 users)]',
      '              DabNodeClosureVar [&0]',
      '          DabNodeTreeBlock []',
      '            DabNodeCall [[??]]',
      '              DabNodeSymbol [:qux]',
      '              DabNodeLiteralNil []',
      '              DabNodeLiteralNil []',
      '              DabNodeSSAGet [R0 [bar]]',
      '              DabNodeSSAGet [R1 [other#1]]',
      '          DabNodeReturn []',
      '            DabNodeLiteralNil []',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:test]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)
  end

  it 'should ssaify var inside if inside while' do
    arglist = DabNode.new
    arglist << DabNodeArgDefinition.new(0, 'bar', nil)

    tree = DabNodeTreeBlock.new

    tree << DabNodeDefineLocalVar.new('foo', DabNodeArg.new(0))

    nif = DabNodeTreeBlock.new
    nif << DabNodeSetLocalVar.new('foo', DabNodeArg.new(1))
    tree << DabNodeIf.new(DabNodeLiteralBoolean.new(true), nif, nil)

    nwhile = DabNodeWhile.new(DabNodeLiteralBoolean.new(true), tree)

    root = DabNodeUnit.new
    func = DabNodeFunction.new('test', nwhile, arglist, false)
    root.add_function(func)

    SSAify.new.run(func)

    array = [
      'DabNodeUnit []',
      '  DabNode []',
      '    DabNodeFunction [test]',
      '      DabNode []',
      '        DabNodeArgDefinition [#0[bar]]',
      '      DabNodeBlockNode []',
      '        DabNodeWhile []',
      '          DabNodeLiteralBoolean [true]',
      '          DabNodeTreeBlock []',
      '            DabNodeSSASet [R0= [foo] (1 users)]',
      '              DabNodeArg [$0]',
      '            DabNodeIf []',
      '              DabNodeLiteralBoolean [true]',
      '              DabNodeTreeBlock []',
      '                DabNodeSSASet [R1= [foo] (1 users)]',
      '                  DabNodeArg [$1]',
      '            DabNodeSSASet [R2= [foo] (0 users)]',
      '              DabNodeSSAPhi [[foo]]',
      '                DabNodeSSAGet [R1 []]',
      '                DabNodeSSAGet [R0 []]',
      '      DabNode []',
      '      DabNodeLiteralNil []',
      '      DabNodeSymbol [:test]',
      '  DabNode []',
      '  DabNode []',
    ]

    expect(root.all_nodes.map(&:simple_info)).to eq(array)
  end
end
