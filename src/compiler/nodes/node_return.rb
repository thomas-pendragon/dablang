require_relative 'node'
require_relative '../processors/check_return_type'
require_relative '../processors/uncomplexify'

class DabNodeReturn < DabNode
  check_with CheckReturnType
  lower_with :normalize_modern_declared_return!
  lower_with Uncomplexify

  attr_accessor :modern_declared_return_type

  def normalize_modern_declared_return!
    return unless modern_declared_return_type

    target_type = modern_declared_return_type
    self.modern_declared_return_type = nil
    return if value.literal_nil?

    literal = value
    if value.is_a?(DabNodeSSAGet) && value.setters.one?
      literal = value.setters.first.value
    end
    if literal.is_a?(DabNodeLiteral)
      literal_type = literal.is_a?(DabNodeLiteralBoolean) ? 'Boolean' : literal.my_type.type_string
      return if literal_type == target_type.type_string
    end

    normalized = DabNodeModernReturnNormalization.new(value.extract, target_type)
    insert(normalized)
    true
  end

  def initialize(value)
    super()
    insert(value)
  end

  def value
    self[0]
  end

  def compile(output)
    if $no_autorelease
      self.active_registers.each do |register|
        reg = "R#{register}"
        output.printex(self, 'RELEASE', reg) unless reg == value.register_string
      end
    end
    output.printex(self, 'RETURN', value.register_string)
  end

  def formatted_source(options)
    "return #{value.formatted_source(options)}"
  end

  def returns_value?
    false
  end

  def uncomplexify_args
    [value]
  end

  def accepts?(arg)
    arg.register? || arg.literal_nil?
  end
end
