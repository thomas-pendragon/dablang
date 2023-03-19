require_relative 'node_base_jump'
require_relative '../processors/flatten_conditional_jump'
require_relative '../processors/uncomplexify'

class DabNodeConditionalJump < DabNodeBaseJump
  attr_reader :target
  attr_reader :if_true, :if_false

  optimize_with FlattenConditionalJump
  lower_with Uncomplexify

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
    self[0]
  end

  def compile(output)
    args = [
      "R#{condition.input_register}",
      if_true.compile_label(output),
      if_false.compile_label(output),
    ]
    output.print('JMP_IF', *args)
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

  def uncomplexify_args
    [condition]
  end

  def accepts?(arg)
    arg.register?
  end

  def formatted_source(options)
    cnd = condition.formatted_source(options)
    "jmp #{cnd} ? B#{if_true.block_index} : B#{if_false.block_index}"
  end
end
