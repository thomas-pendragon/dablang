require_relative 'node_reference.rb'

class DabNodeReferenceLocalVar < DabNodeReference
  def initialize(name)
    super()
    @name = name
  end

  def compiled
    DabNodeLocalVar.new(@name)
  end

  def formatted_source(_options)
    @name
  end
end
