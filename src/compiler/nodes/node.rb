class DabNode
  attr_reader :children
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
    case callback
    when Class
      callback.new.run(item)
    when Symbol
      item.send(callback)
    else
      raise "unknown callback #{callback.class}"
    end
  end

  def run_check_callbacks!
    run_all_processors!(:check_callbacks)
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

  def run_all_processors!(type)
    type = [type] unless type.is_a? Array
    list = type.flat_map { |subtype| self.class.send(subtype) }
    ret = false
    list.each do |item|
      test = self.class.run_callback(self, item)
      ret ||= test
    end
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
  end

  def dup(level = 0)
    ret = super()
    ret.dup_replacements.clear
    ret.dup_replacements[self] = ret
    ret.clear
    ret.parent = nil
    ret.parent_info = self.parent_info
    self.children.each do |child|
      ret.insert(child.dup(level + 1))
      ret.dup_replacements.merge!(child.dup_replacements)
    end
    ret.fixup_dup_replacements!(dup_replacements) if level == 0
    ret
  end

  def fixup_dup_replacements!(dictionary)
    self.children.each { |child| child.fixup_dup_replacements!(dictionary) }
  end

  def insert(child, parent_info = nil)
    child.parent_info = parent_info if parent_info && child.respond_to?(:parent_info=)
    @children << claim(child)
  end

  def claim(child)
    unless child.is_a? DabNode
      child = DabNodeSymbol.new(child)
    end

    child.parent = self
    child
  end

  def inspect
    to_s
  end

  def to_s(show_ids = true)
    tt = self.my_type.type_string
    tt = "#{tt}!".bold if self.my_type.concrete?
    tt = sprintf('(%s)', tt).white
    src = sprintf('%s:%d', self.source_file || '?', self.source_line || -1)
    flags = ''
    exdump = extra_dump.to_s
    exdump = ' ' + exdump.bold unless exdump.empty?
    pinfo = ''
    if parent_info
      pinfo = "#{parent_info}: ".bold
    end
    if show_ids
      pinfo = self.object_id.to_s.bold.blue + ': ' + pinfo
    end
    sprintf('%s%s%s%s %s %s', pinfo, self.class.name, exdump, flags, tt, src.white)
  end

  def dump(show_ids = false, level = 0)
    text = sprintf('%s - %s', '  ' * level, to_s(show_ids))
    text = text.green if constant?
    if has_errors?
      text = if @self_errors.count > 0
               text.light_red.bold + " (#{@self_errors.map(&:message).join(', ')})"
             else
               text.light_red
             end
    end
    err(text)
    @children.each do |child|
      if child.nil?
        err('%s ~ [nil]', '  ' * (level + 1))
      elsif child.is_a? DabNode
        if child.parent != self
          raise "child #{child} is broken, parent is '#{child.parent}', should be '#{self}'"
        end
        child.dump(show_ids, level + 1)
      else
        err('%s ~ %s', '  ' * (level + 1), child.to_s)
      end
    end
  end

  def extra_dump
    ''
  end

  def self_all_nodes(klass)
    klass = [klass] unless klass.is_a? Array
    ret = []
    ret << self if klass.any? { |item| self.is_a? item }
    ret
  end

  def all_nodes(klass)
    klass = [klass] unless klass.is_a? Array
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

  def pre_insert(node)
    @children.unshift(claim(node))
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

  def has_function?(id)
    return true if id == 'print' || id == 'exit'
    self.visit_all(DabNodeFunction) do |function|
      return function if function.identifier == id
    end
    false
  end

  def add_source_part(part)
    @self_source_parts << part
  end

  def add_source_parts(*parts)
    parts.each do |part|
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
    DabTypeAny.new
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
    children
  end

  def <<(*args)
    insert(*args)
    self
  end

  def scoped_self_all_nodes(klass, _node)
    self_all_nodes(klass)
  end

  def scoped_all_nodes(klass)
    node = self
    ret = []
    while node
      ret |= node.scoped_self_all_nodes(klass, self)
      node = node.parent
    end
    ret
  end

  def node_index(node)
    @children.index(node)
  end

  def scope_path
    return '' unless parent
    return '' if self.is_a? DabNodeFunction
    parent.scope_path + '_' + parent.node_index(self).to_s
  end

  def all_ordered_nodes
    all_nodes(Object)
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
    function_parent.children.each_with_index do |node, index|
      ret += node.all_ordered_nodes if index < self_index
    end
    ret = function_parent.previous_nodes(klass) + [function_parent] + ret
    ret = ret.select { |node| node.is_a? klass }
    ret
  end

  def following_nodes(klass)
    return [] unless function_parent
    self_index = function_parent.node_index(self)
    ret = []
    function_parent.children.each_with_index do |node, index|
      test = index > self_index
      test ||= yield(node) if block_given?
      ret += node.all_ordered_nodes if test
    end
    ret += function_parent.following_nodes(klass)
    ret = ret.select { |node| node.is_a? klass }
    ret
  end
end
