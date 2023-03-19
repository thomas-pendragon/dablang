require_relative 'node'
require_relative '../processors/lower_setter'

class DabNodeSetter < DabNode
  after_init LowerSetter

  def initialize(reference, value)
    super()
    insert(reference)
    insert(value)
  end

  def reference
    self[0]
  end

  def value
    self[1]
  end

  def formatted_source(options)
    ref = reference&.formatted_source(options) || '_no_reference'
    val = value&.formatted_source(options) || '_no_value'

    ref + ' = ' + val
  end

  def returns_value?
    false
  end
end
