require_relative 'node_reference.rb'

class DabNodeReferenceIndex < DabNodeReference
  def initialize(base, index)
    super()
    insert(base)
    insert(index)
  end

  def base
    children[0]
  end

  def index
    children[1]
  end

  def formatted_source(options)
    base.formatted_source(options) + '[' + index.formatted_source(options) + ']'
  end
end
