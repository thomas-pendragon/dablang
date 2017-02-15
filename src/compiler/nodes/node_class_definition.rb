require_relative 'node.rb'

class DabNodeClassDefinition < DabNode
  attr_reader :identifier
  attr_reader :number

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    identifier
  end

  def compile(output)
    output.print('START_CLASS', identifier, number)
    output.print('END_CLASS')
  end

  def assign_number(number)
    @number = number
  end
end
