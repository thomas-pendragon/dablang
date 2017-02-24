require_relative 'node.rb'

class DabNodeClassDefinition < DabNode
  attr_reader :identifier
  attr_reader :number

  def initialize(identifier, functions)
    super()
    @identifier = identifier
    @functions = DabNode.new
    functions.each do |fun|
      @functions.insert(fun)
    end
    insert(@functions)
  end

  def extra_dump
    identifier
  end

  def compile(output)
    output.print('START_CLASS', identifier, number)
    output.print('END_CLASS')
    output._print("\n")
    @functions.each do |fun|
      fun.compile(output)
    end
  end

  def assign_number(number)
    @number = number
  end
end
