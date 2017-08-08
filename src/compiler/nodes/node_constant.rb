require_relative 'node.rb'
require_relative '../processors/strip_unused_constant.rb'

class DabNodeConstant < DabNode
  optimize_with StripUnusedConstant

  def initialize(value)
    super()
    insert(value)
  end

  def extra_dump
    "$#{index} (#{references.count} refs)"
  end

  def index
    root.constant_index(self)
  end

  def value
    @children[0]
  end

  def compile(output)
    value.compile_constant(output)
  end

  def extra_value
    value.extra_value
  end

  def real_value
    value.real_value
  end

  def my_type
    value.my_type
  end

  def constant?
    value.constant?
  end

  def references
    root.all_nodes(DabNodeConstantReference).select { |node| node.target == self }
  end
end
