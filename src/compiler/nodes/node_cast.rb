require_relative 'node.rb'

class DabNodeCast < DabNode
  def initialize(value, target_type)
    super()
    @target_type = target_type
    insert(value)
  end

  def value
    self[0]
  end

  def target_type
    @target_type
  end

  def my_type
    target_type
  end

  def compile(output)
    value.compile(output)
    output.printex(self, 'CAST', root.class_index(target_type.type_string))
  end
end
