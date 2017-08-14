require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNodeConstant do
  it 'tracks references' do
    parent = DabNodeTreeBlock.new
    function = DabNodeFunction.new('test', parent, nil)
    unit = DabNodeUnit.new
    unit.add_function(function)

    value = DabNodeLiteralString.new('foo')

    use1 = unit.add_constant(value)
    const = use1.target

    parent << use1

    expect(const.references).to match_array [use1]

    use2 = unit.add_constant(const)
    parent << use2

    expect(const.references).to match_array [use1, use2]
  end
end
