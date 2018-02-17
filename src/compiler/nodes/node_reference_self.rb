require_relative 'node_reference.rb'

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
