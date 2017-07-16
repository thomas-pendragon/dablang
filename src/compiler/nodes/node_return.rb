require_relative 'node.rb'
require_relative '../processors/check_return_type.rb'

class DabNodeReturn < DabNode
  check_with CheckReturnType

  def initialize(value)
    super()
    insert(value)
  end

  def value
    children[0]
  end

  def compile(output)
    value.compile(output)
    output.printex(self, 'RETURN')
  end

  def formatted_source(options)
    'return ' + value.formatted_source(options)
  end

  def returns_value?
    false
  end
end
