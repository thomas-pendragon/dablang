require_relative 'node_base_jump.rb'
require_relative '../processors/flatten_conditional_jump.rb'

class DabNodeConditionalJump < DabNodeBaseJump
  attr_reader :target
  attr_reader :if_true, :if_false

  optimize_with FlattenConditionalJump

  def initialize(condition, if_true, if_false)
    super()
    @if_true = if_true
    @if_false = if_false
    insert(condition)
  end

  def extra_dump
    "-> true: #{if_true.block_index} | false: #{if_false.block_index}"
  end

  def condition
    children[0]
  end

  def compile(output)
    condition.compile(output)
    output.print('JMP_IF', if_true.compile_label(output))
    output.print('JMP', if_false.compile_label(output))
  end

  def replace_target!(from, to)
    @if_true = to if @if_true == from
    @if_false = to if @if_false == from
  end

  def targets
    [@if_true, @if_false]
  end

  def fixup_dup_replacements!(dictionary)
    super
    @if_true = dictionary[@if_true] || @if_true
    @if_false = dictionary[@if_false] || @if_false
  end
end
