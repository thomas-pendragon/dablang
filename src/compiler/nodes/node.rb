require_relative '../parts/module_dump.rb'

class DabNode
  include DabNodeModuleDump

  # attr_reader :children
  attr_accessor :parent
  attr_accessor :parent_info
  attr_accessor :dup_replacements

  class << self
    define_method_chain = proc do |method_name, collection_name|
      define_method(collection_name) do
        ret = safe_instance_variable_get("@#{collection_name}") || []
        if self.superclass < DabNode
          ret |= self.superclass.send(collection_name)
        end
        ret
      end

      define_method(method_name) do |klass|
        name = "@#{collection_name}"
        collection = safe_instance_variable_get(name) || []
        collection << klass
        instance_variable_set(name, collection)
      end
    end

    define_method_chain.call(:check_with, :check_callbacks)
    define_method_chain.call(:after_init, :init_callbacks)
    define_method_chain.call(:lower_with, :lower_callbacks)
    define_method_chain.call(:optimize_with, :optimize_callbacks)
    define_method_chain.call(:strip_with, :strip_callbacks)
    define_method_chain.call(:flatten_with, :flatten_callbacks)
  end

  def self.run_callback(item, callback)
    dab_benchmark(callback) do
      case callback
      when Class
        callback.new.run(item)
      when Symbol
        item.send(callback)
      else
        raise "unknown callback #{callback.class}"
      end
    end
  end

  def run_check_callbacks!
    run_all_processors!(:check_callbacks)
  end

  def init!
    run_all_processors!(:init_callbacks)
  end

  def run_processors!(type)
    type = [type] unless type.is_a? Array
    list = type.flat_map { |subtype| self.class.send(subtype) }
    list.each do |item|
      if self.class.run_callback(self, item)
        err "Run: #{self.class} #{item}\n".yellow.bold if $debug
        return true
      end
    end
    @children.any? { |item| item.run_processors!(type) }
  end

  def sub_run_all_processors!(type)
    type = [type] unless type.is_a? Array
    list = type.flat_map { |subtype| self.class.send(subtype) }
    ret = false
    list.each do |item|
      test = self.class.run_callback(self, item)
      ret ||= test
    end
    ret
  end

  def run_all_processors!(type)
    ret = sub_run_all_processors!(type)
    @children.each do |child|
      test = child.run_all_processors!(type)
      ret ||= test
    end
    ret
  end

  def initialize
    @dup_replacements = {}
    @children = []
    @self_errors = []
    @self_source_parts = []
    @children_cache = [self]
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
    ret.rebuild_children_cache!
    ret
  end

  def fixup_dup_replacements!(dictionary)
    @children.each { |child| child.fixup_dup_replacements!(dictionary) }
  end

  def insert(child, parent_info = nil)
    child.parent_info = parent_info if parent_info && child.respond_to?(:parent_info=)
    @children << claim(child)
    rebuild_children_cache!
    @children
  end

  def pre_insert(child, parent_info = nil)
    child.parent_info = parent_info if parent_info && child.respond_to?(:parent_info=)
    @children.unshift(claim(child))
    rebuild_children_cache!
  end

  def rebuild_children_cache!
    @children_cache = _children_tree.freeze
    parent&.rebuild_children_cache!
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

    child.parent = self
    child
  end

  def extra_dump
    ''
  end

  def self_all_nodes(klass)
    klass = [klass] unless klass.nil? || klass.is_a?(Array)
    ret = []
    ret << self if klass.nil? || klass.any? { |item| self.is_a?(item) }
    ret
  end

  def all_nodes(klass = nil)
    klass = [klass] unless klass.nil? || klass.is_a?(Array)
    ret = self_all_nodes(klass)
    children_nodes.each do |node|
      ret |= node.all_nodes(klass)
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

  def visit_all_and_replace(klass, &block)
    @children = @children.map do |child|
      value = if child.is_a? klass
                yield(child)
              elsif child.is_a? DabNode
                child.visit_all_and_replace(klass, &block)
                child
              else
                child
              end
      value.parent = self
      value
    end
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
    to = to.map { |item| claim(item) }
    if index = @children.index(from)
      @children[index] = to
    end
    @children.flatten!
    rebuild_children_cache!
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
    rebuild_children_cache!
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
    rebuild_children_cache!
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
