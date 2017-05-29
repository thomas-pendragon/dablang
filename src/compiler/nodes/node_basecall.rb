require_relative 'node.rb'

class DabNodeBasecall < DabNode
  def initialize(arglist)
    super()
    arglist&.each { |arg| insert(arg) }
  end

  def args
    children
  end
end
