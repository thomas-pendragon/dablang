require_relative 'node_base_jump'

class DabNodeJump < DabNodeBaseJump
  attr_reader :target

  def initialize(target)
    super()
    @target = target
  end

  def extra_dump
    "->#{target.block_index}"
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

  def formatted_source(_options)
    "jmp B#{target.block_index}"
  end
end
