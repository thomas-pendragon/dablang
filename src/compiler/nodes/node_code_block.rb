require_relative 'node.rb'
require_relative '../processors/check_empty_block.rb'
require_relative '../processors/remove_unreachable_block.rb'
require_relative '../processors/optimize_block_jump.rb'
require_relative '../processors/optimize_block_jump_next.rb'
require_relative '../processors/flatten_code_block.rb'
require_relative '../processors/strip_extra_return.rb'
require_relative '../processors/strip_unused_values.rb'

class DabNodeCodeBlock < DabNode
  check_with CheckEmptyBlock
  lower_with OptimizeBlockJump
  lower_with OptimizeBlockJumpNext
  lower_with StripUnusedValues
  optimize_with RemoveUnreachableBlock
  optimize_with StripExtraReturn
  flatten_with FlattenCodeBlock

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) + (item.formatted_skip_semicolon? ? '' : ';') }
    return '' unless lines.count > 0
    lines.join("\n") + "\n"
  end

  def splice(spliced_node)
    spliced_index = index(spliced_node)

    pre_block = DabNodeCodeBlock.new
    post_block = DabNodeCodeBlock.new

    each_with_index do |node, index|
      node._set_parent(nil)
      pre_block << node if index < spliced_index
      post_block << node if index > spliced_index
    end
    safe_clear
    spliced = yield(post_block)

    spliced.each { |node| raise 'splice block must yield CodeBlock!' unless node.is_a?(DabNodeCodeBlock) }

    first_block = spliced[0]
    pre_block.insert(DabNodeJump.new(first_block))

    blocks = [pre_block, spliced, post_block].flatten
    blocks.each { |block| block.parent_info = nil }

    function&.all_nodes(DabNodeBaseJump)&.each do |node|
      node.replace_target!(self, pre_block)
    end

    replace_with!(blocks)
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
    ret = function.all_nodes(DabNodeBaseJump).select { |jump| jump.targets.include?(self) }
    ret += [function] if block_index == 0
    ret
  end

  def embedded?
    !parent.is_a?(DabNodeBlockNode)
  end

  def unreachable?
    sources.empty?
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
