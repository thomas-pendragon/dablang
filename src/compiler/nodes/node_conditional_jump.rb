require_relative 'node.rb'

class DabNodeConditionalJump < DabNode
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
end
