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
end
