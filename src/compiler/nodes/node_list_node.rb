require_relative 'node'

class DabNodeListNode < DabNode
  attr_reader :separator

  def initialize(value, separator)
    super()
    insert(value)
    @separator = separator
  end

  def value
    self[0]
  end

  def extra_dump
    "(#{@separator})"
  end
end
