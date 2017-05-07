require_relative 'node.rb'
require_relative '../processors/lower_setter.rb'

class DabNodeSetter < DabNode
  lowers_with LowerSetter

  def initialize(reference, value)
    super()
    insert(reference)
    insert(value)
  end

  def reference
    children[0]
  end

  def value
    children[1]
  end

  def formatted_source(options)
    reference.formatted_source(options) + ' = ' + value.formatted_source(options) + ';'
  end
end
