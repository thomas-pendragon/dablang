class ConvertCallToSyscall
  def run(node)
    return unless %w(print exit __usecount).include? node.real_identifier
    syscall = KERNELCODES_REV[node.real_identifier.upcase.gsub('__', '')]
    syscall = DabNodeSyscall.new(syscall, node.args.map(&:dup))
    node.replace_with!(syscall)
    true
  end
end
