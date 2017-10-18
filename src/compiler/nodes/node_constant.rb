require_relative 'node.rb'
require_relative '../processors/strip_unused_constant.rb'

class DabNodeConstant < DabNode
  strip_with StripUnusedConstant

  attr_accessor :asm_position

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

  def symbol_index
    root.symbol_index(self)
  end

  def value
    @children[0]
  end

  def asm_length
    value.asm_length
  end

  def compile_string(output)
    value.compile_string(output)
  end

  def compile_symbol(output)
    output.comment(extra_value)
    output.print("W_SYMBOL _SDAT + #{asm_position}")
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
