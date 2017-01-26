require_relative 'node.rb'

class DabNodeArg < DabNode
  attr_reader :index

  def initialize(index)
    super()
    @index = index
  end

  def extra_dump
    "$#{@index}"
  end

  def compile(output)
    output.print('ARG', @index)
  end
end
