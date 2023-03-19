require_relative 'node_reference'

class DabNodeReferenceMember < DabNodeReference
  def initialize(base, name)
    super()
    insert(base)
    @name = name
  end

  def base
    self[0]
  end

  def name
    @name
  end

  def compiled
    DabNodePropertyGet.new(base.compiled, @name)
  end

  def formatted_source(options)
    base.formatted_source(options) + '.' + name
  end
end
