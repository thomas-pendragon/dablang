class ConvertCallToSyscall
  def run(node)
    return unless %w(print exit).include? node.real_identifier
    syscall = KERNELCODES_REV[node.real_identifier.upcase]
    syscall = DabNodeSyscall.new(syscall, node.args.map(&:dup))
    node.replace_with!(syscall)
    true
  end
end
