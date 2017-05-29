require_relative 'node.rb'

class DabNodeCallBlock < DabNode
  def initialize(body)
    super()
    insert(body)
  end

  def body
    children[0]
  end
end
