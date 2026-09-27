require_relative 'node_syscall'

class DabNodeModernToString < DabNodeSyscall
  late_lower_with :allocate_discarded_result!

  def initialize(value)
    @discarded_result = nil
    super(KERNELCODES_REV.fetch('MODERN_TO_STRING'), [value])
  end

  def my_type
    DabType.parse('String')
  end

  def compile_top_level(output)
    raise 'Modern conversion has no result register' if @discarded_result.nil?

    _compile(output, "R#{@discarded_result}")
  end

private

  def allocate_discarded_result!
    return if parent.is_a?(DabNodeSSASet) || parent.is_a?(DabNodeRegisterSet)
    return unless @discarded_result.nil?

    @discarded_result = function.allocate_ssa
    true
  end
end
