require_relative 'node.rb'

class DabNodeReflect < DabNode
  attr_reader :reflect_type

  def initialize(reflect_type, value)
    super()
    insert(value)
    @reflect_type = reflect_type
  end

  def value
    self[0]
  end

  def compile(output)
    value.compile(output)
    output.printex(self, 'REFLECT', REFLECTION_REV[reflect_type])
  end
end
