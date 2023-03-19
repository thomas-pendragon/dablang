require_relative 'node'

class DabNodeClassVarDefinition < DabNode
  attr_reader :name
  def initialize(name)
    super()
    @name = name
  end
end
