require_relative 'node_syscall'

class DabNodeModernReturnNormalization < DabNodeSyscall
  def initialize(value, target_type)
    @target_type = target_type
    super(KERNELCODES_REV.fetch('MODERN_RETURN_NORMALIZE'), [value, DabNodeClass.new(target_type.type_string)])
  end

  def my_type
    @target_type
  end
end
