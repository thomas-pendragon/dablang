require_relative '../parts/module_dump.rb'
require_relative '../parts/module_processors.rb'

class DabNode
  include DabNodeModuleDump
  include DabNodeModuleProcessors

  # attr_reader :children
  attr_reader :parent
  attr_accessor :dup_replacements
  attr_accessor :dirty

  def initialize
    @parent = nil
    @dup_replacements = {}
    @children = []
    @self_errors = []
    @self_source_parts = []
    @children_cache_new_class = {}
    @dirty = true
    @did_init = false
    @deleted = false
  end

  def depth
    parent ? parent.depth + 1 : 0
  end

  def simple_info
    "#{'  ' * depth}#{self.class} [#{self.extra_dump}]"
  end

  def children_info
    {}
  end

  def last_node
    @children.last
  end

  def dup(level = 0)
    ret = super()
    ret.dup_replacements.clear
    ret.dup_replacements[self] = ret
    ret.safe_clear
    ret.__set_parent(nil)
    @children.each do |child|
      ret.insert(child.dup(level + 1))
      ret.dup_replacements.merge!(child.dup_replacements)
    end
    ret.fixup_dup_replacements!(dup_replacements) if level == 0
    ret.dirty = true
    ret
  end

  def mutate!
    self.dirty = true
  end

  def dirty?
    dirty
  end

  def on_added; end

  def on_removed; end

  def _set_parent(parent)
    if @parent
      on_removed
      @parent.safe_remove_child(self)
    end
    __set_parent(parent)
    on_added if parent
  end

  def __set_parent(parent)
    @parent&.mark_children_cache_dirty!
    @parent = parent
  end

  def fixup_dup_replacements!(dictionary)
    @children.each { |child| child.fixup_dup_replacements!(dictionary) }
  end

  def insert(child)
    mark_children_cache_dirty!
    @children << claim(child)
  end

  def pre_insert(child)
    mark_children_cache_dirty!
    @children.unshift(claim(child))
  end

  def mark_children_cache_dirty!
    @children_cache_new = nil
    @children_cache_new_class = {}
    parent&.mark_children_cache_dirty!
  end

  def _get_children_cache
    if false # TODO: extra debug flag
      old_list = @children_cache_new
      new_list = _children_tree
      if old_list && (new_list != old_list)
        raise 'mismatch'
      end
      @children_cache_new ||= new_list
    else
      @children_cache_new ||= _children_tree
    end
    @children_cache_new
  end

  def _children_tree
    ret = [self]
    @children.each do |child|
      ret += child.all_nodes
    end
    ret
  end

  def claim(child)
    unless child.is_a? DabNode
      child = DabNodeSymbol.new(child)
    end

    child._set_parent(self)
    child
  end

  def extra_debug_dump
    "#{self.class}#{extra_dump}"
  end

  def extra_dump
    ''
  end

  def all_nodes(klass = nil)
    ret = _get_children_cache
    return ret unless klass
    @children_cache_new_class[klass] ||= ret.select do |child|
      child.is_any_of?(klass)
    end
  end

  def count
    @children.count
  end

  def each
    @children.each do |child|
      yield(child)
    end
  end

  def each_with_index
    @children.each_with_index do |child, index|
      yield(child, index)
    end
  end

  def compile_top_level(output)
    if self.respond_to?(:compile_as_ssa)
      return compile_as_ssa(output, nil)
    end
    compile(output)
    raise "#{self.class} should not return value here" if returns_value?
  end

  def compile(output)
    if self.respond_to?(:compile_as_ssa)
      return compile_as_ssa(output, nil)
    end
    err '!'.red * 80
    root.dump
    err '~'.red * 80
    raise "cannot compile #{self.class}"
  end

  def function
    return self if self.is_a? DabNodeFunction
    parent&.function
  end

  def extra_value
    ''
  end

  def [](index)
    @children[index]
  end

  def last
    (count > 0) ? self[count - 1] : nil
  end

  def real_value
    self
  end

  def safe_remove_child(node)
    mark_children_cache_dirty!
    @children -= [node]
  end

  def _remove_child(node)
    safe_remove_child(node)
    node.self_destruct!
  end

  def self_destruct!
    _set_parent(nil)
    @children.each(&:self_destruct!)
    safe_clear
  end

  def add_error(error)
    @self_errors << error
  end

  def errors
    @self_errors + @children.flat_map(&:errors)
  end

  def has_errors?
    errors.count > 0
  end

  def root
    @parent ? @parent.root : self
  end

  def add_source_part(part)
    @self_source_parts << part
  end

  def add_source_parts(*parts)
    parts.compact.each do |part|
      @self_source_parts << part
    end
  end

  def source_parts
    ret = @self_source_parts + @children.flat_map(&:source_parts)
    ret = ret.select { |item| item.is_a? SourceString }
    ret
  end

  def first_source_part
    source_parts.first
  end

  def source_file
    first_source_part&.source_file
  end

  def source_line
    first_source_part&.source_line
  end

  def source_cstart
    source_parts.map(&:source_cstart).compact.min
  end

  def source_cend
    source_parts.map(&:source_cend).compact.max
  end

  def clone_source_parts_from(source)
    @self_source_parts = source.source_parts.dup
  end

  def my_type
    DabTypeObject.new
  end

  def remove!
    parent._remove_child(self)
    all_nodes.each(&:mark_deleted!)
  end

  def mark_deleted!
    @deleted = true
  end

  def deleted?
    @deleted
  end

  def replace_child(from, to)
    mark_children_cache_dirty!
    to = [] if to.nil?
    to = [to] unless to.is_a? Array
    unless index = @children.index(from)
      raise 'replace_child: source not found'
    end
    from.remove!
    to = to.map { |item| claim(item) }
    @children.insert(index, to)
    @children.flatten!
    mark_children_cache_dirty!
  end

  def replace_with!(other)
    parent.replace_child(self, other)
  end

  def constant?
    false
  end

  def formatted_source(_options)
    raise "unknown source for #{self.class.name}"
  end

  def code_dump
    err dirty_formatted_source({})
  end

  def dirty_formatted_source(options)
    formatted_source(options)
  end

  def formatted_skip_semicolon?
    false
  end

  def _indent(text)
    text.lines.map { |line| "  #{line}" }.join
  end

  def ends_with?(klass)
    @children.last.is_a? klass
  end

  def empty?
    @children.count == 0
  end

  def constant_value
    raise "no constant value for #{self.class}"
  end

  def register_filename(output)
    output.register_filename(source_file) if source_file
    @children.each do |child|
      child.register_filename(output)
    end
  end

  def register_filename_new(output)
    output.register_filename_new(source_file) if source_file
    @children.each do |child|
      child.register_filename_new(output)
    end
  end

  def register_filename_new2(output)
    output.register_filename_new2(source_file) if source_file
    @children.each do |child|
      child.register_filename_new2(output)
    end
  end

  def clear
    @children.each do |node|
      node._set_parent(nil)
    end
    safe_clear
  end

  def safe_clear
    @children = []
    mark_children_cache_dirty!
  end

  def map(&block)
    @children.map(&block)
  end

  def flat_map(&block)
    @children.flat_map(&block)
  end

  def sort_by!(&block)
    mark_children_cache_dirty!
    @children.sort_by!(&block)
  end

  def sort!(&block)
    mark_children_cache_dirty!
    @children.sort!(&block)
  end

  def sort_by_array!
    sort! do |a, b|
      a_value = yield(a)
      b_value = yield(b)
      a_value <=> b_value
    end
  end

  def to_a
    self[0..-1]
  end

  def <<(*args)
    insert(*args)
    self
  end

  def node_index(node)
    @children.index(node)
  end

  def index(node)
    @children.index(node)
  end

  def parent_index
    parent&.index(self)
  end

  # TODO: handle nested code blocks
  def all_ordered_nodes(klasses)
    ret = []
    all_nodes.each do |node|
      break if block_given? && (!klasses || node.is_any_of?(klasses)) && yield(node)
      ret << node
    end
    ret = ret.select { |node| node.is_any_of?(klasses) } if klasses
    ret
  end

  def function_parent
    return nil if parent.is_a? DabNodeFunction
    return nil if parent.is_a? DabNodeBlockNode
    parent
  end

  def previous_nodes_in_tree(klass)
    previous_nodes(klass) - all_parents
  end

  def all_parents
    return [] unless parent
    [parent] + parent.all_parents
  end

  def previous_nodes(klass, sender = self)
    return [] unless function_parent
    self_index = function_parent.node_index(self)
    ret = []
    function_parent.each_previous_scope_with_index(sender) do |node, index|
      ret += node.all_ordered_nodes(klass) if index < self_index
    end
    ret = function_parent.previous_nodes(klass, sender) + [function_parent] + ret
    ret = ret.select { |node| node.is_a? klass }
    ret
  end

  def each_previous_scope_with_index(_sender, &block)
    each_with_index(&block)
  end

  def includes?(node)
    all_nodes.include?(node)
  end

  def following_nodes(klasses, unscoped: false, &block)
    return [] unless function_parent
    self_index = function_parent.node_index(self)
    ret = []
    function_parent.each_with_index do |node, index|
      next unless index > self_index
      break if block_given? && (!klasses || node.is_any_of?(klasses)) && yield(node)
      ret += node.all_ordered_nodes(klasses, &block)
    end
    ret += function_parent.following_nodes(klasses, unscoped: unscoped, &block) if unscoped
    ret = ret.select { |node| node.is_any_of?(klasses) } if klasses
    ret
  end

  def returns_value?
    true
  end

  def insert_at(index, node)
    @children.insert(index, claim(node))
    mark_children_cache_dirty!
  end

  def _insert_before(node)
    if parent.is_kind_of_any?([DabNodeBasicBlock, DabNodeTreeBlock])
      index = parent.index(self)
      raise 'no index' unless index
      parent.insert_at(index, node)
    else
      parent._insert_before(node)
    end
  end

  def prepend_in_parent(node)
    parent.insert_at(parent.index(self), node)
  end

  def append_in_parent(node)
    parent.insert_at(parent.index(self) + 1, node)
  end

  def prepend_instruction(node)
    _insert_before(node)
  end

  def extract
    _set_parent(nil)
    self
  end

  def has_function?(*_args)
    false
  end

  def _fixup_ssa_setters(variable, last_setter, possible_setters)
    if possible_setters.count > 1 && possible_setters.all? { |setter| !setter.nil? && setter != last_setter }
      last_setter = nil
    end

    setters = (possible_setters + [last_setter]).compact.uniq

    if setters.count == 1
      return setters.first
    elsif setters.count > 1
      phi = DabNodeSSAPhiBase.new(setters)
      phi_setter = DabNodeSetLocalVar.new(variable.identifier, phi)
      self.append_in_parent(phi_setter)
      return phi_setter
    else
      return last_setter
    end
  end

  def fixup_ssa(variable, last_setter)
    list = @children.dup
    list.each do |child|
      last_setter = child.fixup_ssa(variable, last_setter)
    end
    last_setter
  end

  def fixup_ssa_phi_nodes(setters_mapping)
    @children.each do |child|
      child.fixup_ssa_phi_nodes(setters_mapping)
    end
  end

  def register?
    false
  end

  def accepts?(_arg)
    true
  end

  def cast_to(target_type)
    raise "cannot compile-time cast from #{my_type} to #{target_type}"
  end

  def sort_by(&block)
    @children.sort_by(&block)
  end

  def literal_nil?
    false
  end

  def active_registers
    previous_nodes(DabNodeRegisterSet).map(&:output_register).uniq
  end

  def no_side_effects?
    false
  end
end
