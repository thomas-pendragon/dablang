require_relative 'node.rb'

class DabNodeConstantReference < DabNode
  attr_accessor :index
  def initialize(index)
    super()
    @index = index
  end

  def extra_dump
    "$$#{index}"
  end

  def target
    raise 'no func' unless function
    raise 'no index' unless index
    function.constants[index]
  end

  def extra_value
    target.extra_value
  end

  def real_value
    target.real_value
  end

  def compile(output)
    output.push(self)
  end

  def my_type
    target.my_type
  end

  def constant?
    target.constant?
  end
end
