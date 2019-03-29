class ConvertCallToSyscall
  def run(node)
    return unless %w(print exit __usecount __fetch_int32).include? node.real_identifier

    syscall = KERNELCODES_REV[node.real_identifier.upcase.gsub('__', '')]
    syscall = DabNodeSyscall.new(syscall, node.args.map(&:dup))
    syscall.clone_source_parts_from(node)
    node.replace_with!(syscall)
    true
  end
end
