require_relative 'node.rb'

class DabNodeClassVarDefinition < DabNode
  attr_reader :name
  def initialize(name)
    super()
    @name = name
  end
end
