require_relative 'node.rb'
require_relative '../processors/create_attributes.rb'

BUILTINS = %w[
  print
  exit
  __usecount
  __import_libc
  __import_sdl
  __import_pq
  +
  -
  *
  /
  %
  is
  &&
  ||
  &
  |
  <
  <=
  ==
  !=
  >=
  >
].freeze

class DabNodeUnit < DabNode
  attr_reader :constants
  attr_reader :functions
  attr_reader :classes

  after_init CreateAttributes

  def initialize
    super()
    @functions = DabNode.new
    @constants = DabNode.new
    @classes = DabNode.new
    insert(@functions)
    insert(@constants)
    insert(@classes)
    @class_numbers = STANDARD_CLASSES_REV.dup
    @labels = 0
    @constant_table = {}
    rebuild_available_functions!
  end

  def children_info
    {
      @functions => 'functions',
      @constants => 'constants',
      @classes => 'classes',
    }
  end

  def rebuild_available_functions!
    @available_functions = BUILTINS.map { |value| [value, true] }.to_h
    @functions.each do |function|
      @available_functions[function.identifier] = function
    end
  end

  def class_number(id)
    @class_numbers[id]
  end

  def add_constant(literal)
    const = @constant_table[literal.extra_value] || _create_constant(literal)
    ret = DabNodeConstantReference.new(const)
    ret.clone_source_parts_from(literal)
    ret
  end

  def _create_constant(literal)
    const = DabNodeConstant.new(literal)
    @constants.insert(const)
    sort_order = {
      DabNodeSymbol => 0,
      DabNodeLiteralString => 1,
    }
    @constants.sort_by! do |node|
      raise 'invalid node' unless node.is_a?(DabNodeConstant)
      class_order_name = node.value.class
      class_order = sort_order[class_order_name]
      raise "unknown '#{class_order_name}'" unless class_order
      class_order.to_s + node.extra_value.to_s
    end
    @constant_table[literal.extra_value] = const
    const
  end

  def will_remove_constant(constant)
    @constant_table.delete(constant.extra_value)
  end

  def add_function(function)
    @functions.insert(function)
    @available_functions[function.identifier] = function
  end

  def add_class(klass)
    number = @class_numbers[klass.identifier]
    number ||= USER_CLASSES_OFFSET + @classes.count
    klass.assign_number(number)
    @classes.insert(klass)
    @class_numbers[klass.identifier] = number
  end

  def class_index(name)
    @class_numbers[name] || raise("unknown class #{name}")
  end

  def constant_index(node)
    @constants.index(node)
  end

  def symbol_index(node)
    if $newformat
      return constant_symbols.index(node)
    end
    constant_index(node)
  end

  def compile_old(output)
    output.comment('Dab dev')
    output.print('')
    output.separate

    if $with_cov
      register_filename(output)
      output.separate
    end

    [@constants, @classes].each do |list|
      list.each do |node|
        node.compile(output)
      end
      output.separate
    end
    @functions.sort_by(&:identifier).each do |function|
      function.compile(output)
    end
    output.separate
    output.print('BREAK_LOAD')
    output.separate
    @functions.sort_by(&:identifier).each do |function|
      function.compile_body(output)
      output.separate
    end
    @classes.sort_by(&:identifier).each do |klass|
      klass.functions.sort_by(&:identifier).each do |function|
        function.compile_body(output)
        output.separate
      end
    end
  end

  def constant_symbols
    @constants.to_a.select do |constant|
      constant.value.is_a? DabNodeSymbol
    end
  end

  def constant_strings
    @constants.to_a.select do |constant|
      constant.value.is_a? DabNodeLiteralString
    end
  end

  def compile_new(output)
    output.comment('Dab dev 2')
    output.print('')
    output.separate

    output.print('W_HEADER', 2)
    if $with_cov
      output.print('W_SECTION', '_COVD', '"data"')
      output.print('W_SECTION', '_COVE', '"cove"')
    end
    if constant_strings.count > 0
      output.print('W_SECTION', '_DATA', '"data"')
    end
    output.print('W_SECTION', '_SDAT', '"data"')
    output.print('W_SECTION', '_SYMB', '"symb"')
    if @classes.count > 0
      output.print('W_SECTION', '_CLAS', '"clas"')
    end
    output.print('W_SECTION', '_CODE', '"code"')
    if $feature_reflection
      output.print('W_SECTION', '_FUNC', '"fext"')
    else
      output.print('W_SECTION', '_FUNC', '"func"')
    end
    output.print('W_END_HEADER')
    output.separate

    if $with_cov
      output.label('_COVD')
      register_filename_new(output)
      output.separate

      output.label('_COVE')
      register_filename_new2(output)
      output.separate
    end

    if constant_strings.count > 0
      output.label('_DATA')
      pos = 0
      constant_strings.each do |constant|
        constant.asm_position = pos
        constant.compile_string(output)
        pos += constant.asm_length
      end
      output.separate
    end

    output.label('_SDAT')
    pos = 0
    constant_symbols.each do |constant|
      constant.asm_position = pos
      constant.compile_string(output)
      pos += constant.asm_length
    end
    output.separate

    output.label('_SYMB')
    constant_symbols.each do |constant|
      constant.compile_symbol(output)
    end
    output.separate

    if @classes.count > 0
      output.label('_CLAS')
      @classes.sort_by(&:number).each do |klass|
        klass.compile_definition(output)
      end
      output.separate
    end

    output.label('_CODE')
    output.print('NOP')
    output.separate

    @functions.sort_by(&:identifier).each do |function|
      function.compile_body(output)
      output.separate
    end
    @classes.sort_by(&:identifier).each do |klass|
      klass.functions.sort_by(&:identifier).each do |function|
        function.compile_body(output)
        output.separate
      end
    end

    output.label('_FUNC')
    @functions.sort_by(&:identifier).each do |function|
      function.compile_definition(output)
    end
    @classes.sort_by(&:identifier).each do |klass|
      klass.functions.sort_by(&:identifier).each do |function|
        function.compile_definition(output)
      end
    end
    output.separate
  end

  def compile(output)
    if $newformat
      compile_new(output)
    else
      compile_old(output)
    end
  end

  def remove_constant_node(node)
    node.remove!
  end

  def reorder_constants!
    @constants.children.sort_by!(&:index)
  end

  def formatted_source(options)
    ret = []
    [@constants, @classes, @functions].each do |list|
      list.each do |item|
        ret << item.formatted_source(options)
      end
    end
    ret.join("\n")
  end

  def merge!(another_program)
    another_program.functions.each do |fun|
      @functions.insert(fun)
    end
    another_program.constants.each do |constant|
      @constants.insert(constant)
    end
    another_program.classes.each do |klass|
      @classes.insert(klass)
    end
    another_program.clear!
    rebuild_constant_table!
    rebuild_available_functions!
  end

  def rebuild_constant_table!
    @constant_table = {}
    @constants.each do |constant|
      @constant_table[constant.extra_value] = constant
    end
  end

  def clear!
    self.functions.clear
    self.constants.clear
    self.classes.clear
    @constant_table = {}
  end

  def has_function?(id)
    @available_functions[id]
  end

  def all_functions
    all_nodes(DabNodeFunction)
  end
end
