class DabNode
  attr_reader :children
  attr_accessor :parent
  attr_accessor :parent_info

  class << self
    define_method_chain = proc do |method_name, collection_name|
      define_method(collection_name) do
        ret = instance_variable_get("@#{collection_name}") || []
        if self.superclass.is_a? DabNode
          ret |= self.superclass.send(collection_name)
        end
        ret
      end

      define_method(method_name) do |klass|
        name = "@#{collection_name}"
        collection = instance_variable_get(name) || []
        collection << klass
        instance_variable_set(name, collection)
      end
    end

    define_method_chain.call(:checks_with, :checkers)
    define_method_chain.call(:after_init, :init_callbacks)
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
    list = self.class.checkers
    ret = false
    list.each do |item|
      test = self.class.run_callback(self, item)
      ret ||= test
    end
    @children.each do |child|
      test = child.run_check_callbacks!
      ret ||= test
    end
    ret
  end

  def run_processors!(type)
    list = self.class.send(type)
    list.each do |item|
      return true if self.class.run_callback(self, item)
    end
    @children.any? { |item| item.run_processors!(type) }
  end

  def initialize
    @children = []
    @self_errors = []
    @self_source_parts = []
  end

  def dup
    ret = super
    ret.clear
    ret.parent = nil
    ret.parent_info = self.parent_info
    self.children.each do |child|
      ret.insert(child.dup)
    end
    ret
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

  def dump(level = 0)
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
    text = sprintf('%s - %s%s%s%s %s %s', '  ' * level, pinfo, self.class.name, exdump, flags, tt, src.white)
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
        child.dump(level + 1)
      else
        err('%s ~ %s', '  ' * (level + 1), child.to_s)
      end
    end
  end

  def extra_dump
    ''
  end

  def all_nodes(klass)
    klass = [klass] unless klass.is_a? Array
    ret = []
    ret << self if klass.any? { |item| self.is_a? item }
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
    parent.function
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
    return true if id == 'print' || id == 'exit' || id == 'puts'
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

  def lower!
    children.any?(&:lower!)
  end

  def optimize!
    children.any?(&:optimize!)
  end

  def preoptimize!
    children.any?(&:preoptimize!)
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
    false
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

  def blockify!
    children.any?(&:blockify!)
  end

  def blockish?
    false
  end

  def block_reorder!
    children.any?(&:block_reorder!)
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
end
