require_relative 'node.rb'

class DabNodeUnit < DabNode
  attr_reader :constants
  attr_reader :functions
  attr_reader :classes

  def initialize
    super()
    @functions = DabNode.new
    @constants = DabNode.new
    @classes = DabNode.new
    insert(@functions, 'functions')
    insert(@constants, 'constants')
    insert(@classes, 'classes')
    @class_numbers = STANDARD_CLASSES_REV.dup
    @labels = 0
    @constant_table = {}
  end

  def class_number(id)
    @class_numbers[id]
  end

  def reserve_label
    ret = @labels
    @labels += 1
    "L#{ret}"
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
    @constant_table[literal.extra_value] = const
    const
  end

  def add_function(function)
    @functions.insert(function)
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
    all_nodes(DabNodeConstant).index(node)
  end

  def _items
    [@constants.children, @classes.children, @functions.children]
  end

  def compile(output)
    if $with_cov
      register_filename(output)
      output.separate
    end

    [@constants.children, @classes.children].each do |list|
      list.each do |node|
        node.compile(output)
      end
      output.separate
    end
    @functions.children.each do |function|
      function.compile(output)
    end
    output.separate
    output.print('BREAK_LOAD')
    output.separate
    @functions.children.each do |function|
      function.compile_body(output)
      output.separate
    end
    @classes.children.each do |klass|
      klass.functions.each do |function|
        function.compile_body(output)
        output.separate
      end
    end
  end

  def remove_constant_node(node)
    @constants.remove_child(node)
  end

  def reorder_constants!
    @constants.children.sort_by!(&:index)
  end

  def formatted_source(options)
    _items.flatten(1).map { |item| item.formatted_source(options) }.join("\n")
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
end
