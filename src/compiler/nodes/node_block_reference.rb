require_relative 'node.rb'

class DabNodeBlockReference < DabNode
  def initialize(target)
    super()
    @target = target
    insert(@target.identifier)
  end

  def identifier
    self[0]
  end
end
