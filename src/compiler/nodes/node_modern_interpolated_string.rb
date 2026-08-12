require_relative 'node'
require_relative 'node_instance_call'
require_relative '../processors/uncomplexify'

class DabNodeModernStringAppend < DabNode
  lower_with Uncomplexify
  late_lower_with :convert_to_call

  def initialize(left, right)
    super()
    insert(left)
    insert(right)
  end

  def left
    self[0]
  end

  def right
    self[1]
  end

  def my_type
    DabType.parse('String')
  end

  def uncomplexify_args
    [left, right]
  end

  def accepts?(argument)
    argument.register?
  end

  def formatted_source(options)
    "#{left.formatted_source(options)} + #{right.formatted_source(options)}"
  end

private

  def convert_to_call
    left_value = left
    right_value = right
    left_value.extract
    right_value.extract
    replace_with!(DabNodeInstanceCall.new(left_value, '+', [right_value], nil))
    true
  end
end

class DabNodeModernInterpolatedString < DabNode
  late_lower_with :allocate_result_register!

  attr_reader :output_register, :result_type

  def initialize(components, source:, consumed:)
    super()
    unless components.is_a?(Array) && !components.empty?
      raise ArgumentError.new('Modern interpolated String requires one or more nonempty components')
    end

    @source = source.freeze
    @consumed = consumed
    @output_register = nil
    @result_type = DabType.parse('String').freeze
    expression = components.drop(1).inject(components.fetch(0)) do |left, right|
      DabNodeModernStringAppend.new(left, right)
    end
    insert(expression)
  end

  def value
    self[0]
  end

  def my_type
    result_type
  end

  def returns_value?
    false
  end

  def compile(output)
    if value.is_a?(DabNodeInstanceCall) && output_register.nil?
      raise 'Modern interpolated String has no allocated append result register'
    end
    unless value.respond_to?(:compile_as_ssa)
      raise "cannot compile #{value.class} as a Modern interpolated String"
    end

    value.compile_as_ssa(output, output_register)
  end

  def compile_as_ssa(output, output_register)
    return compile(output) if output_register.nil?

    value.compile_as_ssa(output, output_register)
  end

  def formatted_source(_options)
    @source
  end

private

  def allocate_result_register!
    return if @consumed
    return unless value.is_a?(DabNodeModernStringAppend)
    return unless output_register.nil?

    @output_register = function.allocate_ssa
    true
  end
end
