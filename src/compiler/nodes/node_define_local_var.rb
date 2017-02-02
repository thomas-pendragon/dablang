require_relative 'node.rb'

class DabNodeDefineLocalVar < DabNode
  attr_accessor :index
  attr_reader :identifier

  def initialize(identifier, value, type)
    super()
    @identifier = identifier
    insert(value)
    type ||= DabNodeType.new(nil)
    insert(type)
  end

  def value
    children[0]
  end

  def var_type
    children[1]
  end

  def real_identifier
    identifier
  end

  def compile(output)
    raise 'no index' unless @index
    value.compile(output)
    output.comment("var #{index} #{identifier}")
    output.print('SET_VAR', index)
  end
end
