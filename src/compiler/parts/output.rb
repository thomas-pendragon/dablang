class DabOutput
  def initialize
    @filenames = {}
    @labelcount = {}
  end

  def next_label(kind = 'L')
    @labelcount[kind] ||= 0
    @labelcount[kind] += 1
    sprintf('%s%d', kind, @labelcount[kind])
  end

  def start_function
    print('START_FUNCTION')
  end

  def register_filename(filename)
    unless @filenames[filename]
      @filenames[filename] = @filenames.count + 1
      print('COV_FILE', @filenames[filename], "\"#{filename}\"")
    end
  end

  def get_filename(filename)
    ret = @filenames[filename]
    raise "unregistered filename <#{filename}>" unless ret
    ret
  end

  def _print(t)
    if @last_p == " \n" && t == " \n"
      return
    end
    @last_p = t
    # errn t
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

    _print sprintf('/* %-12s */ ', @comment.to_s[0...12].gsub(/[^a-zA-Z0-9 \-\._]/, ''))

    t = if @label
          sprintf('%-12s: ', @label.to_s[0...12])
        else
          ' ' * 14
        end
    _print t

    t = args[0] + ' ' + args[1..-1].map { |item| _printable(item) }.join(', ')

    _print(t)
    _print("\n")

    @comment = nil
    @label = nil
  end

  def printex(node, *args)
    if $with_cov && node.source_line
      print('COV', get_filename(node.source_file), node.source_line)
    end
    print(*args)
  end

  def _printable(item)
    if item.is_a? String
      return item.gsub("\n", '\\n')
    end
    item
  end

  def push(node)
    raise 'wat' unless node.is_a? DabNodeConstantReference
    comment(node.extra_value)
    print('PUSH_CONSTANT', node.index)
  end

  def function(name, class_index, n_local_vars)
    print('START_FUNCTION', name, class_index, n_local_vars)
    yield
    print('END_FUNCTION')
    separate
  end

  def separate
    _print(" \n")
  end
end
