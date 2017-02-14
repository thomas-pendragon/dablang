require_relative 'node.rb'

class DabNodeClass < DabNode
  attr_reader :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    identifier
  end
end
