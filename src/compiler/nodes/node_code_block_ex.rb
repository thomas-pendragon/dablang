require_relative 'node.rb'

class DabNodeCodeBlockEx < DabNode
  attr_reader :label
  attr_accessor :successor

  def initialize(label)
    super()
    @label = label
  end

  def extra_dump
    "!.#{label}"
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
    ret.map(&:label)
  end

  def compile(output)
    output.label(label)
    @children.each do |child|
      child.compile(output)
    end
  end
end
