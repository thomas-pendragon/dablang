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
  MAX_FOLDED_BYTES = (1 << 31) - 1

  optimize_with :fold_static_components!
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
    @static_components_folded = false
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

  def no_side_effects?
    @static_components_folded && @consumed
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

  def fold_static_components!
    return if @static_components_folded
    return unless value.is_a?(DabNodeModernStringAppend)

    folded_value = resolve_static_string(value, {}, {})
    return unless folded_value

    @static_components_folded = true
    value.replace_with!(
      DabNodeModernStringAppend.new(
        DabNodeLiteralString.new(''.b, modern_source: true),
        DabNodeLiteralString.new(folded_value, modern_source: true)
      )
    )
    true
  end

  def resolve_static_string(node, memo, resolving)
    return memo[node] if memo.key?(node)
    return if resolving[node]

    resolving[node] = true
    begin
      resolved = case node
                 when DabNodeLiteralString
                   node.constant_value
                 when DabNodeModernStringAppend
                   resolve_static_append(node, memo, resolving)
                 when DabNodeModernInterpolatedString
                   resolve_static_string(node.value, memo, resolving)
                 when DabNodeSSAGet
                   setters = node.setters
                   resolve_static_string(setters.fetch(0).value, memo, resolving) if setters.one?
                 end
      memo[node] = resolved
    ensure
      resolving.delete(node)
    end
  end

  def resolve_static_append(node, memo, resolving)
    left = resolve_static_string(node.left, memo, resolving)
    return unless left

    right = resolve_static_string(node.right, memo, resolving)
    return unless right
    return unless static_concat_in_range?(left.bytesize, right.bytesize)

    left + right
  end

  def static_concat_in_range?(left_size, right_size)
    left_size <= MAX_FOLDED_BYTES && right_size <= MAX_FOLDED_BYTES - left_size
  end

  def allocate_result_register!
    return if @consumed
    return unless value.is_a?(DabNodeModernStringAppend)
    return unless output_register.nil?

    @output_register = function.allocate_ssa
    true
  end
end
