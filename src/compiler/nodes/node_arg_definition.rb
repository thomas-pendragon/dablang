require_relative 'node.rb'

class DabNodeArgDefinition < DabNode
  attr_accessor :index
  attr_reader :identifier

  def initialize(index, identifier)
    super()
    @index = index
    @identifier = identifier
  end

  def extra_dump
    "##{@index}[#{identifier}]"
  end
end
