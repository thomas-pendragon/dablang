require_relative 'node.rb'

class DabNodeConstantReference < DabNode
  attr_accessor :index
  def initialize(index)
    super()
    @index = index
  end

  def extra_dump
    " $$#{index}"
  end

  def target
    raise 'no func' unless function
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
end
