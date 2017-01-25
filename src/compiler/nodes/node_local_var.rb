require_relative 'node.rb'

class DabNodeLocalVar < DabNode
  attr_accessor :index

  def initialize(identifier)
    super()
    insert(identifier)
  end

  def identifier
    children[0]
  end

  def real_identifier
    identifier.extra_value
  end

  def compile(output)
    raise 'no index' unless @index
    output.comment("var #{index} #{identifier.extra_value}")
    output.print('VAR', index)
  end
end
