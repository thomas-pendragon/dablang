require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNode do
  it 'splices simple node' do
    parent = DabNodeCodeBlock.new
    body = DabNodeCodeBlock.new
    p1 = DabNodeSymbol.new(:p1)
    p2 = DabNodeSymbol.new(:p2)
    p3 = DabNodeSymbol.new(:p3)
    body << p1
    body << p2
    body << p3
    parent << body

    p4 = DabNodeSymbol.new(:p4)
    p5 = DabNodeSymbol.new(:p5)
    p4b = DabNodeCodeBlock.new
    p4b << p4
    p5b = DabNodeCodeBlock.new
    p5b << p5

    body.splice(p2) do |rest|
      jump = DabNodeJump.new(rest)
      jumpb = DabNodeCodeBlock.new
      jumpb << jump
      ret = [p4b, jumpb, p5b]
      ret
    end

    parent.dump(false, 0, {}, skip_output: true)
    expect(parent.all_nodes(DabNodeSymbol).map(&:symbol)).to eq(%i[p1 p4 p5 p3])
  end

  it 'splices if node' do
    before_if = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('before if'))
    condition = DabNodeLiteralNumber.new(15)
    on_true_node = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('on true'))
    on_false_node = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('on false'))
    on_true = DabNodeCodeBlock.new
    on_false = DabNodeCodeBlock.new
    on_true << on_true_node
    on_false << on_false_node
    after_if = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('after if'))
    if_node = DabNodeIf.new(condition, on_true, on_false)

    parent = DabNodeCodeBlock.new
    parent << before_if
    parent << if_node
    parent << after_if

    superparent = DabNodeFunction.new('test', parent, nil)

    FlattenIf.new.run(if_node)

    superparent.dump(false, 0, {}, skip_output: true)
    expect(superparent.blocks.count).to eq(5)
  end

  it 'splices if node without else' do
    before_if = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('before if'))
    condition = DabNodeLiteralNumber.new(15)
    on_true_node = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('on true'))
    on_true = DabNodeCodeBlock.new
    on_true << on_true_node
    after_if = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('after if'))
    if_node = DabNodeIf.new(condition, on_true, nil)

    parent = DabNodeCodeBlock.new
    parent << before_if
    parent << if_node
    parent << after_if

    superparent = DabNodeFunction.new('test', parent, nil)

    FlattenIf.new.run(if_node)

    superparent.dump(false, 0, {}, skip_output: true)
    expect(superparent.blocks.count).to eq(4)
  end

  it 'splices double if node without else' do
    before_if = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('before if'))
    condition = DabNodeLiteralNumber.new(15)
    on_true_node = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('on true'))
    on_true = DabNodeCodeBlock.new
    on_true << on_true_node
    after_if = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('after if'))
    if_node = DabNodeIf.new(condition, on_true, nil)

    second_condition = DabNodeLiteralNumber.new(42)
    second_on_true_node = DabNodeSyscall.new(0, DabNode.new << DabNodeLiteralString.new('another on true'))
    second_on_true = DabNodeCodeBlock.new
    second_on_true << second_on_true_node
    second_if_node = DabNodeIf.new(second_condition, second_on_true, nil)

    parent = DabNodeCodeBlock.new
    parent << before_if
    parent << if_node
    parent << second_if_node
    parent << after_if

    superparent = DabNodeFunction.new('test', parent, nil)

    superparent.dump(false, 0, {}, skip_output: true)

    FlattenIf.new.run(superparent.all_nodes(DabNodeIf).first)

    superparent.dump(false, 0, {}, skip_output: true)

    FlattenIf.new.run(superparent.all_nodes(DabNodeIf).first)

    superparent.dump(false, 0, {}, skip_output: true)

    expect(superparent.blocks.count).to eq(7)
  end

  it 'optimizes constant if (true)' do
    on_true = DabNodeSymbol.new(:on_true)
    on_false = DabNodeSymbol.new(:on_false)
    condition = DabNodeLiteralBoolean.new(true)
    if_node = DabNodeIf.new(condition, on_true, on_false)
    parent = DabNode.new << if_node
    OptimizeConstantIf.new.run(if_node)
    list = [
      'DabNode',
      'DabNodeSymbol:on_true',
    ]
    expect(parent.all_nodes.map(&:extra_debug_dump)).to eq list
  end

  it 'optimizes constant if (false)' do
    on_true = DabNodeSymbol.new(:on_true)
    on_false = DabNodeSymbol.new(:on_false)
    condition = DabNodeLiteralBoolean.new(false)
    if_node = DabNodeIf.new(condition, on_true, on_false)
    parent = DabNode.new << if_node
    OptimizeConstantIf.new.run(if_node)
    list = [
      'DabNode',
      'DabNodeSymbol:on_false',
    ]
    expect(parent.all_nodes.map(&:extra_debug_dump)).to eq list
  end
end
