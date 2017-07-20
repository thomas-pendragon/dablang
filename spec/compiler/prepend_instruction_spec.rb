require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  it 'prepends node at instruction level' do
    @top_block = DabNodeCodeBlock.new
    @inner_block = DabNodeCodeBlock.new

    @literal1 = DabNodeLiteralString.new('foo')
    @args = DabNode.new
    @args << @literal1

    @nop1 = DabNodeSymbol.new(:nop1)
    @call1 = DabNodeCall.new('foo', @args, nil)
    @nop2 = DabNodeSymbol.new(:nop2)

    @top_block << @inner_block
    @inner_block << @nop1
    @inner_block << @call1
    @inner_block << @nop2

    @new_nop = DabNodeSymbol.new(:new_nop)

    @literal1.prepend_instruction(@new_nop)

    list = [@nop1, @new_nop, @call1, @nop2]

    expect(@inner_block.to_a).to eq list
  end
end
