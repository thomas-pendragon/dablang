require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabType do
  it 'allows to assign from other types' do
    t_int32 = DabTypeInt32.new
    t_nil = DabTypeNil.new

    expect(t_int32.can_assign_from?(t_nil)).to eq(true)
  end
end
