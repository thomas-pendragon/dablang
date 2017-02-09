class DabOutput
  def start_function
    print('START_FUNCTION')
  end

  def _print(t)
    errn t
    Kernel.print t
  end

  def comment(text)
    @comment = text
  end

  def label(text)
    @label = text
  end

  def print(*args)
    return _print("\n") if args.count == 0 || args[0].nil?

    _print sprintf('/* %-12s */ ', @comment.to_s[0...12])

    t = if @label
          sprintf('%-12s: ', @label.to_s[0...12])
        else
          ' ' * 14
        end
    _print t

    t = args.join(', ').to_s

    _print(t)
    _print("\n")

    @comment = nil
    @label = nil
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
    print('')
  end
end
