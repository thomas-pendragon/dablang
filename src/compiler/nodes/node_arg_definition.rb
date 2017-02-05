require_relative 'node.rb'

class DabNodeArgDefinition < DabNode
  attr_accessor :index
  attr_reader :identifier
  attr_reader :my_type

  def initialize(index, identifier, type)
    super()
    @index = index
    @identifier = identifier
    @my_type = (type || DabNodeType.new(nil)).dab_type
  end

  def extra_dump
    "##{@index}[#{identifier}]"
  end
end
