require_relative 'node.rb'

class DabNodeListNode < DabNode
  attr_reader :separator

  def initialize(value, separator)
    super()
    insert(value)
    @separator = separator
  end

  def value
    children[0]
  end

  def extra_dump
    "(#{@separator})"
  end
end
