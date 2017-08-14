require_relative 'node.rb'
require_relative '../processors/check_empty_block.rb'
require_relative '../processors/remove_empty_block.rb'

class DabNodeCodeBlock < DabNode
  check_with CheckEmptyBlock
  lower_with RemoveEmptyBlock

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) + (item.formatted_skip_semicolon? ? '' : ';') }
    return '' unless lines.count > 0
    lines.join("\n") + "\n"
  end

  def extra_dump
    ret = "!.#{block_index}"
    ret += ' [emb]' if embedded?
    ret
  end

  def jump_block?
    return false unless @children.count == 1
    child = @children[0]
    return false unless child.is_a? DabNodeJump
    child.target
  end

  def ends_with_jump?
    ret = @children.last
    return false unless ret.is_a? DabNodeJump
    ret
  end

  def all_jump_labels
    ret = []
    all_nodes(DabNodeBaseJump).each do |jump|
      ret |= jump.targets
    end
    ret.map(&:block_index)
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

  def block_index
    function&.block_index(self)
  end

  def next_block
    return nil unless block_index
    function.blocks[block_index + 1]
  end

  def sources
    ret = internal_sources
    ret += [function] if block_index == 0
    ret
  end

  def internal_sources
    function.all_nodes(DabNodeBaseJump).select { |jump| jump.targets.include?(self) }
  end

  def embedded?
    !parent.is_a?(DabNodeBlockNode)
  end

  def unreachable?
    sources.empty?
  end

  def internally_unreachable?
    internal_sources.empty?
  end

  def merge_with!(another_block)
    another_block.each do |child|
      insert(child)
    end
    another_block.safe_clear
    another_block.remove!
  end

  def returns?
    all_nodes(DabNodeReturn).count > 0
  end

  def multiple_returns?
    all_nodes(DabNodeReturn).count > 1
  end
end
