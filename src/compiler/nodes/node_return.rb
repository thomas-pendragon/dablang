require_relative 'node.rb'

class DabNodeReturn < DabNode
  def initialize(value)
    super()
    insert(value)
  end

  def value
    children[0]
  end

  def compile(output)
    value.compile(output)
    output.printex(self, 'RETURN', '1')
  end

  def formatted_source(options)
    'return ' + value.formatted_source(options)
  end

  def returns_value?
    false
  end
end
