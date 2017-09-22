require_relative 'node_reference.rb'

class DabNodeReferenceInstVar < DabNodeReference
  def initialize(name)
    super()
    @name = name
  end

  def compiled
    DabNodeInstanceVar.new(@name)
  end

  def formatted_source(_options)
    @name
  end
end
