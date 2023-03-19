require_relative 'node'
require_relative '../processors/create_attributes'

BUILTINS = SYSCALLS + EXTRA_STD_CALLS + %w[
  print
  exit
  define_method
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
  attr_accessor :start_offset

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
    @start_offset = 0
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
    ret = @class_numbers[id]
    unless ret
      errap @class_numbers
      raise "class '#{id}' (#{id.class}) not found"
    end
    ret
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
    @constants.sort_by_array! do |node|
      raise 'invalid node' unless node.is_a?(DabNodeConstant)

      class_order_name = node.value.class
      class_order = sort_order[class_order_name]
      raise "unknown '#{class_order_name}'" unless class_order

      text = class_order.to_s + node.extra_value.to_s
      [
        node.upper_ring? ? 0 : 1,
        node.source_ring_index || 0,
        text,
      ]
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
    constant_symbols.index(node)
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

    output.print('W_HEADER', 3)
    output.print('W_OFFSET', start_offset)
    if $with_cov
      output.print('W_SECTION', '_COVD', '"data"')
      output.print('W_SECTION', '_COVE', '"cove"')
    end
    if constant_strings.count > 0
      output.print('W_SECTION', '_DATA', '"data"')
    end

    output.print('W_SECTION', '_CODE', '"code"')

    custom_classes = @classes.to_a.reject(&:standard?)
    unless custom_classes.empty?
      output.print('W_SECTION', '_CLAS', '"clas"')
    end

    output.print('W_SECTION', '_SDAT', '"symd"')
    output.print('W_SECTION', '_SYMB', '"symb"')

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

    unless custom_classes.empty?
      output.label('_CLAS')
      custom_classes.sort_by(&:number).each do |klass|
        klass.compile_definition(output)
      end
      output.separate
    end

    output.label('_SDAT')
    pos = 0
    constant_symbols.each do |constant|
      next if constant.upper_ring?

      constant.asm_position = pos
      constant.compile_string(output)
      pos += constant.asm_length
    end
    output.separate

    # TODO: handle when all symbols are from upper ring
    output.label('_SYMB')
    constant_symbols.each do |constant|
      next if constant.upper_ring?

      constant.compile_symbol(output)
    end
    output.separate

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
    compile_new(output)
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

  attr_reader :class_numbers

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
    new_offset = [self.start_offset, another_program.start_offset].max
    another_program.class_numbers.each do |klass, number|
      @class_numbers[klass] = number
    end
    self.start_offset = new_offset
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

  def class_names
    @classes.map { |node| node.identifier._to_s }
  end
end
