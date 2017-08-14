require_relative 'node.rb'

class DabNodeBasicBlock < DabNode
  def extra_dump
    block_index.to_s
  end

  def block_index
    parent_index
  end

  def compile_label(output = nil)
    @compile_label ||= output.next_label
  end

  def compile(output)
    unless block_index == 0 && sources.count == 1
      output.label(compile_label(output))
    end
    @children.each do |child|
      child.compile(output)
      output.print('POP', 1) if child.returns_value?
    end
    if @children.count == 0
      output.print('NOP')
    end
  end

  def sources
    ret = internal_sources
    ret += [function] if block_index == 0
    ret
  end

  def internal_sources
    function.all_nodes(DabNodeBaseJump).select { |jump| jump.targets.include?(self) }
  end
end
