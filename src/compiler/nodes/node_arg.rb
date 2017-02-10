require_relative 'node.rb'

class DabNodeArg < DabNode
  attr_reader :index
  attr_reader :my_type

  def initialize(index, type)
    super()
    @index = index
    @my_type = type
  end

  def extra_dump
    "$#{@index}"
  end

  def compile(output)
    output.print('PUSH_ARG', @index)
  end

  def constant?
    true
  end
end
