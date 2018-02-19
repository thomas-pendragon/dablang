require_relative 'node.rb'

class DabNodeArgDefinition < DabNode
  attr_accessor :index
  attr_reader :identifier
  attr_accessor :my_type

  def initialize(index, identifier, type, default_value)
    super()
    insert(default_value) if default_value
    @index = index
    @identifier = identifier
    @my_type = type&.dab_type || DabTypeObject.new
  end

  def default_value
    self[0]
  end

  def extra_dump
    "##{@index}[#{identifier}]"
  end

  def formatted_source(_options)
    @identifier
  end
end
