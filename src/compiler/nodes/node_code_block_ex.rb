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

  def compile(output)
    output.label(label)
    @children.each do |child|
      child.compile(output)
    end
  end
end
