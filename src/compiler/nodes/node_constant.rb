require_relative 'node.rb'
require_relative '../processors/strip_unused_constant.rb'

class DabNodeConstant < DabNode
  strip_with StripUnusedConstant

  def initialize(value)
    super()
    insert(value)
    @references = []
  end

  def remove!
    root.will_remove_constant(self)
    super
  end

  def extra_dump
    "$#{index} (#{references.count} refs)"
  end

  def index
    root.constant_index(self)
  end

  def value
    @children[0]
  end

  def compile(output)
    value.compile_constant(output)
  end

  def extra_value
    value.extra_value
  end

  def real_value
    value.real_value
  end

  def my_type
    value.my_type
  end

  def constant?
    value.constant?
  end

  def constant_value
    value.constant_value if constant?
  end

  def register_reference(reference)
    @references << reference
  end

  def unregister_reference(reference)
    @references.delete(reference)
  end

  def references
    @references
  end

  def formatted_source(options)
    'const[' + value.formatted_source(options) + ']'
  end
end
