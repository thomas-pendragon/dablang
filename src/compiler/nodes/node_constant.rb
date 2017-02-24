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

  def compile(output)
    output.comment(index.to_s)
    @children[0].compile_constant(output)
  end

  def extra_value
    @children[0].extra_value
  end

  def real_value
    @children[0].real_value
  end

  def my_type
    @children[0].my_type
  end

  def constant?
    @children[0].constant?
  end
end
