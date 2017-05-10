require_relative 'node.rb'
require_relative '../processors/simplify_constant_property.rb'

class DabNodePropertyGet < DabNode
  optimize_with SimplifyConstantProperty

  def initialize(value, identifier)
    super()
    insert(value)
    insert(identifier)
  end

  def value
    @children[0]
  end

  def identifier
    @children[1]
  end

  def real_identifier
    identifier.extra_value
  end

  def compile(output)
    value.compile(output)
    output.push(identifier)
    output.comment(".#{real_identifier}")
    output.printex(self, 'INSTCALL', 0, 1)
  end

  def constant?
    value.constant?
  end

  def simplify_constant
    if real_identifier == 'class'
      if value.my_type.concrete?
        return DabNodeLiteralString.new(value.my_type.type_string)
      end
    end
    nil
  end

  def formatted_source(options)
    value.formatted_source(options) + '.' + real_identifier
  end
end
