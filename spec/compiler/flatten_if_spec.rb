require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  it 'flattens double if' do
    if1 = DabNodeIf.new(DabNodeArg.new(0), DabNodeCodeBlock.new, nil)
    if2 = DabNodeIf.new(DabNodeArg.new(0), DabNodeCodeBlock.new, nil)
    program = DabNodeCodeBlock.new << if1 << if2
    args = DabNode.new << DabNodeArgDefinition.new(0, 'a', nil)
    superparent = DabNodeFunction.new('foo', program, args, nil)

    FlattenIf.new.run(superparent.all_nodes(DabNodeIf).first)
    FlattenIf.new.run(superparent.all_nodes(DabNodeIf).first)

    CheckJumpTargets.new.run(superparent.all_nodes(DabNodeConditionalJump).first)
  end
end
