require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNodeCast, uint8: true do
  it 'calculates correct cast requirement' do
    type1 = DabType.parse('Uint8')
    type2 = DabType.parse('Fixnum')
    type3 = DabType.parse('String')

    expect(type1.can_assign_from?(type1)).to eq true
    expect(type1.can_assign_from?(type2)).to eq true
    expect(type1.can_assign_from?(type3)).to eq false

    expect(type1.requires_cast?(type1)).to eq false
    expect(type1.requires_cast?(type2)).to eq true
    expect(type1.requires_cast?(type3)).to eq false
  end

  it 'lowers setter with cast' do
    value = DabNodeLiteralNumber.new(42)
    type = DabType.parse('Uint8')
    localvar = DabNodeSetLocalVar.new('localvar', value, type)
    result = ConvertSetValue.new.run(localvar)
    expect(result).to eq true
    expect(localvar.value).to be_kind_of DabNodeCast
  end
end
