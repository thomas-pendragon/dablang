require_relative 'node.rb'
require_relative '../processors/simplify_class_property.rb'

class DabNodePropertyGet < DabNode
  optimize_with SimplifyClassProperty

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

  def formatted_source(options)
    value.formatted_source(options) + '.' + real_identifier
  end
end
