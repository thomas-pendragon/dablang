require_relative 'node.rb'
require_relative '../processors/check_empty_block.rb'
require_relative '../processors/remove_unreachable_block.rb'
require_relative '../processors/optimize_block_jump.rb'
require_relative '../processors/optimize_block_jump_next.rb'
require_relative '../processors/flatten_code_block.rb'
require_relative '../processors/strip_extra_return.rb'

class DabNodeCodeBlock < DabNode
  check_with CheckEmptyBlock
  lower_with OptimizeBlockJump
  lower_with OptimizeBlockJumpNext
  optimize_with RemoveUnreachableBlock
  optimize_with StripExtraReturn
  flatten_with FlattenCodeBlock

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) }
    return '' unless lines.count > 0
    lines.join("\n") + "\n"
  end

  def splice(node)
    index = children.index(node)
    rest_block = DabNodeCodeBlock.new
    children[(index + 1)..-1].each do |sub_rest|
      rest_block.insert(sub_rest)
    end
    children.pop(rest_block.children.count + 1)
    spliced = yield(rest_block)
    first_block = spliced[0]
    insert(DabNodeJump.new(first_block))
    blocks = [self, spliced, rest_block].flatten
    blocks.each { |block| block.parent_info = nil }
    replace_with!(blocks)
  end

  def extra_dump
    ret = "!.#{block_index}"
    ret += ' [emb]' if embedded?
    ret
  end

  def jump_block?
    return false unless children.count == 1
    child = children[0]
    return false unless child.is_a? DabNodeJump
    child.target
  end

  def ends_with_jump?
    ret = children.last
    return false unless ret.is_a? DabNodeJump
    ret
  end

  def all_jump_labels
    ret = []
    visit_all(DabNodeBaseJump) do |jump|
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
    another_block.children.each do |child|
      insert(child)
    end
    another_block.clear
    another_block.remove!
  end

  def returns?
    all_nodes(DabNodeReturn).count > 0
  end

  def multiple_returns?
    all_nodes(DabNodeReturn).count > 1
  end
end
