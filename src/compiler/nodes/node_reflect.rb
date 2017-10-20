require_relative 'node.rb'

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
    if @klass
      klass = root.class_index(@klass)
      output.print('Q_SET_REFLECT2', "R#{output_register}", "S#{value.symbol_index}", REFLECTION_REV[reflect_type], klass)
    else
      output.print('Q_SET_REFLECT', "R#{output_register}", "S#{value.symbol_index}", REFLECTION_REV[reflect_type])
    end
  end
end
