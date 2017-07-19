require_relative 'node_base_jump.rb'

class DabNodeJump < DabNodeBaseJump
  attr_reader :target
  def initialize(target)
    super()
    @target = target
  end

  def extra_dump
    "->#{target.block_index}"
  end

  def condition
    self[0]
  end

  def compile(output)
    output.print('JMP', target.compile_label(output))
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
