require_relative 'node_base_jump.rb'

class DabNodeConditionalJump < DabNodeBaseJump
  attr_reader :target
  attr_reader :if_true, :if_false

  def initialize(condition, if_true, if_false)
    super()
    @if_true = if_true
    @if_false = if_false
    insert(condition)
  end

  def extra_dump
    "-> true: #{if_true.label} | false: #{if_false.label}"
  end

  def condition
    children[0]
  end

  def compile(output)
    condition.compile(output)
    output.print('JMP_IF', if_true.label)
    output.print('JMP', if_false.label)
  end

  def replace_target!(from, to)
    @if_true = to if @if_true == from
    @if_false = to if @if_false == from
  end

  def targets
    [@if_true, @if_false]
  end

  def optimize!
    if condition.constant?
      test = condition.constant_value
      replace_with!(DabNodeJump.new(test ? if_true : if_false))
      true
    else
      super
    end
  end
end