require_relative 'node'

class DabNodeReflect < DabNode
  attr_reader :reflect_type

  def initialize(reflect_type, value, klass)
    super()
    insert(value)
    @reflect_type = reflect_type
    @klass = klass
  end

  def value
    self[0]
  end

  def compile_as_ssa(output, output_register)
    output.comment(self.extra_value)
    klass = if @klass
              root.class_index(@klass)
            else
              -1
            end
    output.print('REFLECT', "R#{output_register}", "S#{value.symbol_index}", REFLECTION_REV[reflect_type], klass)
  end
end
