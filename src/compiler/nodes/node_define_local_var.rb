require_relative 'node.rb'

class DabNodeDefineLocalVar < DabNode
  attr_accessor :index
  attr_reader :identifier

  def initialize(identifier, value)
    super()
    @identifier = identifier
    insert(value)
  end

  def value
    children[0]
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
