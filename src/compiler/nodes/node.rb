class DabNode
  attr_reader :parent, :children
  attr_writer :parent

  def initialize
    @children = []
  end

  def insert(child)
    unless child.is_a? DabNode
      child = DabNodeSymbol.new(child)
    end

    child.parent = self
    @children << child
  end

  def dump(level = 0)
    err('%s - %s %s', '  ' * level, self.class.name, extra_dump)
    @children.each do |child|
      if child.is_a? DabNode
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
    if self.is_a? klass
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
end
