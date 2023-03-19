require_relative 'node_reference'

class DabNodeReferenceSelf < DabNodeReference
  def initialize
    super()
  end

  def compiled
    DabNodeSelf.new
  end

  def formatted_source(_options)
    'self'
  end
end
