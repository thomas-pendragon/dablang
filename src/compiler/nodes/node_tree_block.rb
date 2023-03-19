require_relative 'node'
require_relative '../processors/flatten_tree_block'

class DabNodeTreeBlock < DabNode
  flatten_with FlattenTreeBlock

  def build_from_tree(current_block, blocks)
    each do |node|
      if node.is_a?(DabNodeTreeBlock)
        current_block = node.build_from_tree(current_block, blocks)
      else
        node._set_parent(nil)
        current_block << node
      end
    end
    current_block
  end

  def topmost?
    !parent.is_a?(DabNodeTreeBlock)
  end

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) + (item.formatted_skip_semicolon? ? '' : ';') }
    return '' unless lines.count > 0

    "#{lines.join("\n")}\n"
  end

  def last_node
    ret = super
    if ret.is_a? DabNodeTreeBlock
      ret.last_node
    else
      ret
    end
  end
end
