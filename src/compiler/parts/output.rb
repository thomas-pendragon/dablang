class DabOutput
  def initialize(context)
    @filenames = {}
    @labelcount = {}
    @context = context
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

  def register_filename_new(filename)
    unless @filenames[filename]
      @filenames[filename] = @filenames.count + 1
      @filenamelength ||= 0
      @filenamepos ||= {}
      @filenamepos[filename] = @filenamelength
      print('W_STRING', "\"#{filename}\"")
      @filenamelength += filename.length + 1
    end
  end

  def register_filename_new2(filename)
    @filenamepos2 ||= {}
    unless @filenamepos2[filename]
      @filenamepos2[filename] = true
      pos = @filenamepos[filename]
      print('W_COV_FILE', "_COVD + #{pos}")
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
    @context.stdout.print t
  end

  def comment(text)
    @comment = text
  end

  def label(text)
    @label = text
  end

  def print(*args)
    args = args.compact

    return _print("\n") if args.count == 0 || args[0].nil?

    if @label
      _print(sprintf("%s%s:\n", ' ' * 19, @label))
    end

    if !@comment.to_s.strip.empty?
      _print sprintf('/* %-12s */ ', @comment.to_s.gsub('*/', '')[0...12].gsub('*/', '').tr("\n", '.'))
    else
      _print ' ' * 19
    end

    _print ' ' * 14

    argsmap = args[1..-1]
              .flatten
              .map { |item| _printable(item) }
              .map(&:to_s)
              .select(&:present?)
              .join(', ')

    t = args[0] + ' ' + argsmap

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
    node.compile(self)
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
