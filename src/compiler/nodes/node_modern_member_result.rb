require_relative 'node'

class DabNodeModernMemberResult < DabNode
  late_lower_with :allocate_result_register!

  attr_reader :output_register, :result_type

  def initialize(value, consumed: false)
    super()
    @output_register = nil
    @result_type = DabType.parse('Int32').freeze
    @consumed = consumed
    insert(value)
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
    raise 'Modern member result has no allocated output register' if output_register.nil?
    raise "cannot compile #{value.class} as a Modern member result" unless value.respond_to?(:compile_as_ssa)

    value.compile_as_ssa(output, output_register)
  end

  def compile_as_ssa(output, output_register)
    return compile(output) if output_register.nil?

    value.compile_as_ssa(output, output_register)
  end

  def formatted_source(options)
    value.formatted_source(options)
  end

private

  def allocate_result_register!
    return if @consumed
    return unless output_register.nil?

    @output_register = function.allocate_ssa
    true
  end
end
