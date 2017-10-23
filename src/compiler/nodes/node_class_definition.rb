require_relative 'node.rb'

class DabNodeClassDefinition < DabNode
  attr_reader :identifier
  attr_reader :number

  after_init :extract_literal

  def initialize(identifier, parent, functions)
    super()
    @identifier = identifier
    @parent_class = parent
    @functions = DabNode.new
    functions.each do |fun|
      @functions.insert(fun)
    end
    insert(@functions)
    insert(DabNodeSymbol.new(identifier))
  end

  def extract_literal
    ExtractLiteral.new.run(node_identifier)
  end

  def node_identifier
    self[1]
  end

  def functions
    @functions
  end

  def extra_dump
    identifier
  end

  def compile_definition(output)
    parent_number = @parent_class ? root.class_number(@parent_class) : 0
    output.comment(identifier)
    output.print('W_CLASS', number, parent_number, node_identifier.symbol_index)
  end

  def compile(output)
    parent_number = @parent_class ? root.class_number(@parent_class) : 0
    output.printex(self, 'DEFINE_CLASS', identifier, number, parent_number)
    @functions.each do |fun|
      fun.compile(output)
    end
  end

  def assign_number(number)
    @number = number
  end

  def formatted_source(options)
    ret = "class #{identifier}\n{\n"
    functions = @functions.map { |fun| fun.formatted_source(options) }
    ret += _indent(functions.join("\n"))
    ret += "}\n"
    ret
  end
end
