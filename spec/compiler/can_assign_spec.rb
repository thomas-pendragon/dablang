require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabType do
  it 'allows to assign from other types' do
    t_int32 = DabTypeInt32.new
    t_nil = DabTypeNil.new
    t_fixnum = DabTypeFixnum.new
    t_string = DabTypeString.new
    t_object = DabTypeObject.new

    expect(t_object.can_assign_from?(t_int32)).to eq(true)

    expect(t_int32.can_assign_from?(t_nil)).to eq(true)
    expect(t_int32.can_assign_from?(t_fixnum)).to eq(true)

    expect(t_fixnum.can_assign_from?(t_string)).to eq(false)
  end
end
