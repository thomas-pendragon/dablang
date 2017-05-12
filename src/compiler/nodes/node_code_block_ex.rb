require_relative 'node.rb'
require_relative '../processors/check_empty_block.rb'
require_relative '../processors/remove_unreachable_block.rb'
require_relative '../processors/optimize_block_jump.rb'
require_relative '../processors/optimize_block_jump_next.rb'

class DabNodeCodeBlockEx < DabNode
  check_with CheckEmptyBlock
  optimize_with OptimizeBlockJump
  optimize_with OptimizeBlockJumpNext
  optimize_with RemoveUnreachableBlock

  def extra_dump
    "!.#{block_index}"
  end

  def blockify!
    children.each_with_index do |item, index|
      next unless item.blockish?
      rest_block = function.new_codeblock_ex
      children[(index + 1)..-1].each do |sub_rest|
        rest_block.insert(sub_rest)
      end
      children.pop(rest_block.children.count + 1)

      insert(item.unblockify!(rest_block))
      return true
    end
    false
  end

  def block_reorder!
    return true if flatten_jump!
    super
  end

  def jump_block?
    return false unless children.count == 1
    child = children[0]
    return false unless child.is_a? DabNodeJump
    child.target
  end

  def flatten_jump!
    return false unless child_target = jump_block?

    function.visit_all(DabNodeBaseJump) do |jump|
      jump.replace_target!(self, child_target)
    end
    remove!
    true
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
    output.label(compile_label(output))
    @children.each do |child|
      child.compile(output)
    end
    if @children.count == 0
      output.print('NOP')
    end
  end

  def block_index
    function.block_index(self)
  end

  def next_block
    function.blocks[block_index + 1]
  end

  def sources
    ret = function.all_nodes(DabNodeBaseJump).select { |jump| jump.targets.include?(self) }
    ret += [function] if block_index == 0
    ret
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
end
