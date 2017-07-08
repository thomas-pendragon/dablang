require_relative 'node.rb'

class DabNodeAttribute < DabNode
  def initialize(name, arglist)
    super()
    insert(name)
    arglist&.each { |item| insert(item) }
  end

  def name
    children[0]
  end

  def arglist
    children[1..-1]
  end

  def real_identifier
    identifier.extra_value
  end
end
