require_relative 'node_reference'

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

class DabNodeReferenceClassVar < DabNodeReference
  def initialize(name)
    super()
    @name = name
  end

  def compiled
    DabNodeClassVar.new(@name)
  end

  def formatted_source(_options)
    @name
  end
end
