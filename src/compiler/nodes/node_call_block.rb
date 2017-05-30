require_relative 'node.rb'

class DabNodeCallBlock < DabNode
  def initialize(body, arglist = nil)
    super()
    insert(body, 'body')
    insert(arglist, 'arglist') if arglist
  end

  def body
    children[0]
  end

  def arglist
    children[1]
  end
end
