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

  def functions
    @functions
  end

  def extra_dump
    identifier
  end

  def compile(output)
    output.printex(self, 'DEFINE_CLASS', identifier, number)
    @functions.each do |fun|
      fun.compile(output)
    end
  end

  def assign_number(number)
    @number = number
  end

  def formatted_source(options)
    ret = "class #{identifier}\n{\n"
    functions = @functions.children.map { |fun| fun.formatted_source(options) }
    ret += _indent(functions.join("\n"))
    ret += "}\n"
    ret
  end
end
