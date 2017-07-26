require_relative '../parts/module_dump.rb'
require_relative '../parts/module_processors.rb'

class DabNode
  include DabNodeModuleDump
  include DabNodeModuleProcessors

  # attr_reader :children
  attr_accessor :parent
  attr_accessor :parent_info
  attr_accessor :dup_replacements

  define_processors!

  def initialize
    @dup_replacements = {}
    @children = []
    @self_errors = []
    @self_source_parts = []
  end

  def dup(level = 0)
    ret = super()
    ret.dup_replacements.clear
    ret.dup_replacements[self] = ret
    ret.clear
    ret.parent = nil
    ret.parent_info = self.parent_info
    @children.each do |child|
      ret.insert(child.dup(level + 1))
      ret.dup_replacements.merge!(child.dup_replacements)
    end
    ret.fixup_dup_replacements!(dup_replacements) if level == 0
    ret.mark_children_cache_dirty!
    ret
  end

  def fixup_dup_replacements!(dictionary)
    @children.each { |child| child.fixup_dup_replacements!(dictionary) }
  end

  def insert(child, parent_info = nil)
    child.parent_info = parent_info if parent_info && child.respond_to?(:parent_info=)
    @children << claim(child)
    mark_children_cache_dirty!
    @children
  end

  def pre_insert(child, parent_info = nil)
    child.parent_info = parent_info if parent_info && child.respond_to?(:parent_info=)
    @children.unshift(claim(child))
    mark_children_cache_dirty!
  end

  def mark_children_cache_dirty!
    @children_cache_new = nil
    parent&.mark_children_cache_dirty!
  end

  def _get_children_cache
    @children_cache_new = _children_tree.freeze
    @children_cache_new
  end

  def _children_tree
    ret = [self]
    @children.each do |child|
      ret |= child._children_tree
    end
    ret
  end

  def claim(child)
    unless child.is_a? DabNode
      child = DabNodeSymbol.new(child)
    end

    child.parent&.mark_children_cache_dirty!
    child.parent = self
    child
  end

  def extra_dump
    ''
  end

  def all_nodes(klass = nil)
    ret = _get_children_cache
    if klass
      ret = ret.select do |child|
        child.is_any_of?(klass)
      end
    end
    ret
  end

  def visit_all(klass, options = {}, &block)
    klass = [klass] unless klass.is_a? Array
    if klass.any? { |item| self.is_a? item }
      yield(self) unless options[:skip_self]
    end

    children_nodes.each { |node| node.visit_all(klass, &block) }
  end

  def children_nodes
    @children.select { |child| child.is_a? DabNode }
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

  def compile(output); end

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

  def real_value
    self
  end

  def remove_child(node)
    @children -= [node]
    mark_children_cache_dirty!
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
    parent.remove_child(self)
  end

  def replace_child(from, to)
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
    raise 'no constant value'
  end

  def register_filename(output)
    output.register_filename(source_file) if source_file
    @children.each do |child|
      child.register_filename(output)
    end
  end

  def clear
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
    @children.sort_by!(&block)
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

  # TODO: handle nested code blocks
  def all_ordered_nodes(klasses)
    ret = []
    all_nodes.each do |node|
      break if block_given? && node.is_any_of?(klasses) && yield(node)
      ret << node
    end
    ret = ret.select { |node| node.is_any_of?(klasses) }
    ret
  end

  def function_parent
    return nil if parent.is_a? DabNodeFunction
    return nil if parent.is_a? DabNodeBlockNode
    parent
  end

  def previous_nodes(klass)
    return [] unless function_parent
    self_index = function_parent.node_index(self)
    ret = []
    function_parent.each_with_index do |node, index|
      ret += node.all_ordered_nodes(klass) if index < self_index
    end
    ret = function_parent.previous_nodes(klass) + [function_parent] + ret
    ret = ret.select { |node| node.is_a? klass }
    ret
  end

  def following_nodes(klasses, unscoped: false, &block)
    return [] unless function_parent
    self_index = function_parent.node_index(self)
    ret = []
    function_parent.each_with_index do |node, index|
      next unless index > self_index
      break if block_given? && node.is_any_of?(klasses) && yield(node)
      ret += node.all_ordered_nodes(klasses, &block)
    end
    ret += function_parent.following_nodes(klasses, &block) if unscoped
    ret = ret.select { |node| node.is_any_of?(klasses) }
    ret
  end

  def returns_value?
    true
  end

  def insert_at(index, node)
    @children.insert(index, claim(node))
    mark_children_cache_dirty!
  end

  def _insert_before(node, before_node)
    if parent.is_a?(DabNodeCodeBlock)
      index = parent.index(before_node)
      raise 'no index' unless index
      parent.insert_at(index, node)
    else
      parent._insert_before(node, parent)
    end
  end

  def prepend_instruction(node)
    _insert_before(node, self)
  end
end
