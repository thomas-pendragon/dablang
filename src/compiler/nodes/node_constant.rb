require_relative 'node.rb'

class DabNodeConstant < DabNode
  attr_accessor :index
  def initialize(value, index)
    super()
    insert(value)
    @index = index
  end

  def extra_dump
    "$#{index}"
  end

  def value
    @children[0]
  end

  def compile(output)
    output.comment(index.to_s)
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
end
