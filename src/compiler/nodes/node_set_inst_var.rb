require_relative 'node.rb'

class DabNodeSetInstVar < DabNode
  attr_reader :identifier

  def initialize(identifier, value)
    super()
    @identifier = identifier
    insert(value)
  end

  def extra_dump
    "<#{identifier}>"
  end

  def value
    children[0]
  end

  def compile(output)
    value.compile(output)
    output.print('SET_INSTVAR', identifier[1..-1])
  end

  def formatted_source(options)
    identifier + ' = ' + value.formatted_source(options)
  end

  def returns_value?
    false
  end
end
