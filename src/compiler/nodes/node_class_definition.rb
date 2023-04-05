require_relative 'node'

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

  def children_info
    {
      functions => 'functions',
      node_identifier => 'identifier',
    }
  end

  def extract_literal
    ExtractLiteral.new.run(node_identifier) unless standard?
  end

  def node_identifier
    self[1]
  end

  def functions
    @functions
  end

  def extra_dump
    "#{identifier} [n= #{@number}]"
  end

  def compile_definition(output)
    parent_number = @parent_class ? root.class_number(@parent_class) : 0
    output.comment(identifier)
    output.print('W_CLASS', number, parent_number, node_identifier.symbol_index)
  end

  def has_class_function?(name)
    return true if name == 'new'

    !!functions.to_a.detect do
      test = _1.identifier.to_s == name && _1.is_static?
      # errap ['look for',name,'here:',_1.identifier.to_s,',static?',_1.is_static?,'TEST:',test]
      test
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

  def standard?
    number < USER_CLASSES_OFFSET
  end
end
