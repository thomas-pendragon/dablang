require_relative 'node'
require_relative '../processors/strip_unused_values'
require_relative '../processors/strip_extra_return'
require_relative '../processors/optimize_block_jump_next'
require_relative '../processors/remove_unreachable_block'
require_relative '../processors/optimize_block_jump'

class DabNodeBasicBlock < DabNode
  lower_with StripUnusedValues
  lower_with OptimizeBlockJumpNext
  lower_with OptimizeBlockJump
  optimize_with StripExtraReturn
  optimize_with RemoveUnreachableBlock

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
      child.compile_top_level(output)
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

  def returns?
    all_nodes(DabNodeReturn).count > 0
  end

  def multiple_returns?
    all_nodes(DabNodeReturn).count > 1
  end

  def ends_with_jump?
    ret = @children.last
    return false unless ret.is_a? DabNodeJump

    ret
  end

  def next_block
    return nil unless block_index

    parent[block_index + 1]
  end

  def merge_with!(another_block)
    another_block.each do |child|
      child._set_parent(nil)
      insert(child)
    end
    another_block.safe_clear
    another_block.remove!
  end

  def unreachable?
    sources.empty?
  end

  def internally_unreachable?
    internal_sources.empty?
  end

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) + (item.formatted_skip_semicolon? ? '' : ';') }
    return '' unless lines.count > 0

    label = "B#{block_index}:\n"
    post = "\n"
    if options[:skip_unused_labels]
      label = '' if internally_unreachable?
      post = ''
    end
    label + lines.join("\n") + post
  end

  def formatted_skip_semicolon?
    true
  end
end
