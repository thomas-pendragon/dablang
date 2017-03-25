class DabNode
  attr_reader :parent, :children
  attr_writer :parent
  attr_accessor :parent_info

  def initialize
    @children = []
    @self_errors = []
    @self_source_parts = []
  end

  def insert(child, parent_info = nil)
    child.parent_info = parent_info if child.respond_to? :parent_info=
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
    tt = sprintf('(%s)', self.my_type.type_string).white
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

  def visit_all(klass, &block)
    klass = [klass] unless klass.is_a? Array
    if klass.any? { |item| self.is_a? item }
      yield(self)
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
    return true if id == 'print'
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
    @self_source_parts + @children.flat_map(&:source_parts)
  end

  def source_file
    source_parts.first&.source_file
  end

  def source_line
    source_parts.first&.source_line
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
    @children.map! do |node|
      if node == from
        claim(to)
      else
        node
      end
    end
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
end
