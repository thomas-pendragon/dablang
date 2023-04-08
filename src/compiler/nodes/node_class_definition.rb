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

  def add_function(fn)
    functions.insert(fn)
  end

  def compile_definition(output)
    parent_number = @parent_class ? root.class_number(@parent_class) : 0
    output.comment(identifier)
    output.print('W_CLASS', number, parent_number, node_identifier.symbol_index)
  end

  def all_functions
    functions.to_a + parent_functions
  end

  def parent_functions
    if number == 0
      []
    elsif @parent_class
      errap ['find parent for', identifier, '::', @parent_class]
      root.find_class(@parent_class).all_functions
    else
      []
    end
  end

  def has_class_function?(name)
    # errap(all_functions.map { [identifier, '.', _1.identifier, (_1.is_static? ? ' (static)' : '')].join })
    !!all_functions.detect do
      _1.identifier.to_s == name && _1.is_static?
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
