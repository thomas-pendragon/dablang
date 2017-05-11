require_relative 'node_base_jump.rb'

class DabNodeJump < DabNodeBaseJump
  attr_reader :target
  def initialize(target)
    super()
    @target = target
  end

  def extra_dump
    "->#{target.label}"
  end

  def condition
    children[0]
  end

  def compile(output)
    output.print('JMP', target.label)
  end

  def replace_target!(from, to)
    @target = to if @target == from
  end

  def targets
    [@target]
  end

  def fixup_dup_replacements!(dictionary)
    super
    @target = dictionary[@target] || @target
  end
end
