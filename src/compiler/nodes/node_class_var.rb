require_relative 'node.rb'

class DabNodeClassVar < DabNode
  attr_accessor :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    @identifier
  end

  def compile(output)
    output.print('PUSH_INSTVAR', identifier[1..-1])
  end
end
