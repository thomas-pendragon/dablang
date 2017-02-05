class DabNode
  attr_reader :parent, :children
  attr_writer :parent

  def initialize
    @children = []
    @self_errors = []
    @self_source_parts = []
  end

  def insert(child)
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
    err('%s - %s %s %s %s', '  ' * level, self.class.name, extra_dump, tt, src.white)
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

  def source_parts
    @self_source_parts + @children.flat_map(&:source_parts)
  end

  def source_file
    source_parts.first&.source_file
  end

  def source_line
    source_parts.first&.source_line
  end

  def clone_source_parts_from(source)
    @self_source_parts = source.source_parts.dup
  end

  def my_type
    DabTypeAny.new
  end
end
