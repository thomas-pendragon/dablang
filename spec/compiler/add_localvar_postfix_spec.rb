require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe AddLocalvarPostfix do
  before do
    #        | func main()
    #        | {
    # def1   |   var a = "foo";
    # print1 |   puts(a);
    #        |   {
    # print2 |     puts(a);
    # def2   |     var a = 12;
    # print3 |     puts(a);
    # set1   |     a = 123; // DabNodeSetLocalVar
    # print4 |     puts(a);
    # set2   |     a = "bar"; // DabNodeSetter
    # print5 |     puts(a);
    #        |   }
    # print6 |   puts(a);
    # set3   |   a = "xx";
    # print7 |   puts(a);
    # def3   |   var a = "xyz";
    # print8 |   puts(a);
    #        | }

    @top_block = DabNodeTreeBlock.new
    @inner_block = DabNodeTreeBlock.new

    @literal1 = DabNodeLiteralString.new('foo')
    @literal2 = DabNodeLiteralNumber.new(12)
    @literal3 = DabNodeLiteralNumber.new(123)
    @literal4 = DabNodeLiteralString.new('bar')
    @literal5 = DabNodeLiteralString.new('xx')
    @literal6 = DabNodeLiteralString.new('xyz')

    @def1 = DabNodeDefineLocalVar.new('a', @literal1)
    @def2 = DabNodeDefineLocalVar.new('a', @literal2)
    @def3 = DabNodeDefineLocalVar.new('a', @literal6)

    @ref1 = DabNodeReferenceLocalVar.new('a')

    @set1 = DabNodeSetLocalVar.new('a', @literal3)
    @set2 = DabNodeSetter.new(@ref1, @literal4)
    @set3 = DabNodeSetLocalVar.new('a', @literal5)

    @var1 = DabNodeLocalVar.new('a')
    @var2 = DabNodeLocalVar.new('a')
    @var3 = DabNodeLocalVar.new('a')
    @var4 = DabNodeLocalVar.new('a')
    @var5 = DabNodeLocalVar.new('a')
    @var6 = DabNodeLocalVar.new('a')
    @var7 = DabNodeLocalVar.new('a')
    @var8 = DabNodeLocalVar.new('a')

    @print1 = DabNodeSyscall.new(0, [@var1])
    @print2 = DabNodeSyscall.new(0, [@var2])
    @print3 = DabNodeSyscall.new(0, [@var3])
    @print4 = DabNodeSyscall.new(0, [@var4])
    @print5 = DabNodeSyscall.new(0, [@var5])
    @print6 = DabNodeSyscall.new(0, [@var6])
    @print7 = DabNodeSyscall.new(0, [@var7])
    @print8 = DabNodeSyscall.new(0, [@var8])

    @inner_block << @print2
    @inner_block << @def2
    @inner_block << @print3
    @inner_block << @set1
    @inner_block << @print4
    @inner_block << @set2
    @inner_block << @print5

    @top_block << @def1
    @top_block << @print1
    @top_block << @inner_block
    @top_block << @print6
    @top_block << @set3
    @top_block << @print7
    @top_block << @def3
    @top_block << @print8

    @root = DabNodeUnit.new
    @root.add_function(DabNodeFunction.new('fun1', @top_block, nil, false))
  end

  # - DabNodeUnit
  #   - functions: DabNode
  #     - DabNodeFunction fun1
  #       - arglist: DabNode
  #       - blocks: DabNodeBlockNode
  #         - DabNodeTreeBlock !.0
  #           - DabNodeDefineLocalVar <a>
  #             - DabNodeLiteralString "foo"
  #           - DabNodeSyscall #0 PRINT
  #             - DabNodeLocalVar <a>
  #           - DabNodeTreeBlock !.
  #             - DabNodeSyscall #0 PRINT
  #               - DabNodeLocalVar <a>
  #             - DabNodeDefineLocalVar <a>
  #               - DabNodeLiteralNumber 12
  #             - DabNodeSyscall #0 PRINT
  #               - DabNodeLocalVar <a>
  #             - DabNodeSetLocalVar <a>
  #               - DabNodeLiteralNumber 123
  #             - DabNodeSyscall #0 PRINT
  #               - DabNodeLocalVar <a>
  #             - DabNodeSetter
  #               - DabNodeReferenceLocalVar a
  #               - DabNodeLiteralString "bar"
  #             - DabNodeSyscall #0 PRINT
  #               - DabNodeLocalVar <a>
  #           - DabNodeSyscall #0 PRINT
  #             - DabNodeLocalVar <a>
  #           - DabNodeSetLocalVar <a>
  #             - DabNodeLiteralString "xx"
  #           - DabNodeSyscall #0 PRINT
  #             - DabNodeLocalVar <a>
  #           - DabNodeDefineLocalVar <a>
  #             - DabNodeLiteralString "xyz"
  #           - DabNodeSyscall #0 PRINT
  #             - DabNodeLocalVar <a>
  #   - constants: DabNode
  #   - classes: DabNode

  let :users1 do
    [@def1, @var1, @var2, @var6, @set3, @var7]
  end

  let :users2 do
    [@def2, @var3, @set1, @var4, @ref1, @var5]
  end

  let :users3 do
    [@def3, @var8]
  end

  it 'should find var1 users' do
    expect(@def1.all_users).to eq(users1)
  end

  it 'should find set2 ordered_nodes' do
    all_ordered_nodes = [
      @set2,
      @ref1,
      @literal4,
    ]
    expect(@set2.all_ordered_nodes(DabNode)).to eq(all_ordered_nodes)
  end

  it 'should find var2 following nodes' do
    def2_following_nodes = [
      @print3,
      @var3,
      @set1,
      @literal3,
      @print4,
      @var4,
      @set2,
      @ref1,
      @literal4,
      @print5,
      @var5,
    ]
    expect(@def2.following_nodes(DabNode)).to eq(def2_following_nodes)
  end

  it 'should find var2 users', xfocus: true do
    expect(@def2.all_users).to eq(users2)
  end

  it 'should find var3 users' do
    expect(@def3.all_users).to eq(users3)
  end

  it 'should process first var' do
    AddLocalvarPostfix.new.run(@def1)
    expect(@def1.all_users).to eq(users1)
    users1.each { |user| expect(user.identifier).to eq('a#1') }
    users2.each { |user| expect(user.identifier).to eq('a') }
    users3.each { |user| expect(user.identifier).to eq('a') }
  end

  it 'should process second var' do
    AddLocalvarPostfix.new.run(@def2)
    users1.each { |user| expect(user.identifier).to eq('a') }
    users2.each { |user| expect(user.identifier).to eq('a#1') }
    users3.each { |user| expect(user.identifier).to eq('a') }
  end

  it 'should process both vars' do
    AddLocalvarPostfix.new.run(@def1)
    AddLocalvarPostfix.new.run(@def2)
    users1.each { |user| expect(user.identifier).to eq('a#1') }
    users2.each { |user| expect(user.identifier).to eq('a#2') }
  end

  it 'should process all vars' do
    AddLocalvarPostfix.new.run(@def1)
    AddLocalvarPostfix.new.run(@def2)
    AddLocalvarPostfix.new.run(@def3)
    users1.each { |user| expect(user.identifier).to eq('a#1') }
    users2.each { |user| expect(user.identifier).to eq('a#2') }
    users3.each { |user| expect(user.identifier).to eq('a#3') }
  end

  it 'should process all vars in reverse order' do
    AddLocalvarPostfix.new.run(@def3)
    AddLocalvarPostfix.new.run(@def2)
    AddLocalvarPostfix.new.run(@def1)
    users1.each { |user| expect(user.identifier).to eq('a#3') }
    users2.each { |user| expect(user.identifier).to eq('a#2') }
    users3.each { |user| expect(user.identifier).to eq('a#1') }
  end
end
