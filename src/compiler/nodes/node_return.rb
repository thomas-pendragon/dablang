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
    output.print('RETURN', '1')
  end
end
