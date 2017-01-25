class DabOutput
  def start_function
    print('START_FUNCTION')
  end

  def comment(text)
    t = sprintf('/* %-12s */ ', text.to_s[0...12])
    errn t
    Kernel.print t
    @cmt = true
  end

  def print(*args)
    comment('') unless @cmt
    t = args.join(', ').to_s
    err t
    puts t
    @cmt = false
  end

  def push(node)
    raise 'wat' unless node.is_a? DabNodeConstantReference
    comment(node.extra_value)
    print('PUSH_CONSTANT', node.index)
  end

  def function(name, n_local_vars)
    print('START_FUNCTION', name, n_local_vars)
    yield
    print('END_FUNCTION')
  end
end
