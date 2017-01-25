require_relative 'node.rb'

class DabNodeDefineLocalVar < DabNode
  attr_accessor :index

  def initialize(identifier, value)
    super()
    insert(identifier)
    insert(value)
  end

  def identifier
    children[0]
  end

  def value
    children[1]
  end

  def real_identifier
    identifier.extra_value
  end

  def compile(output)
    raise 'no index' unless @index
    value.compile(output)
    output.comment("var #{index} #{identifier.extra_value}")
    output.print('SET_VAR', index)
  end
end
