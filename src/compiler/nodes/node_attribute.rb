require_relative 'node.rb'

class DabNodeAttribute < DabNode
  def initialize(name, arglist)
    super()
    insert(name)
    arglist&.each { |item| insert(item) }
  end

  def name
    self[0]
  end

  def arglist
    self[1..-1]
  end

  def real_identifier
    name.extra_value
  end

  def formatted_source(_options)
    real_identifier
  end
end
