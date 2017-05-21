class DabBaseContext
  attr_reader :stream
  def initialize(stream)
    @stream = stream
  end

  def read_identifier(*args)
    @stream.read_identifier(*args)
  end

  def read_operator(*args)
    @stream.read_operator(*args)
  end

  def read_any_operator(*args)
    @stream.read_any_operator(*args)
  end

  def read_string(*args)
    @stream.read_string(*args)
  end

  def read_number(*args)
    @stream.read_number(*args)
  end

  def read_keyword(*args)
    @stream.read_keyword(*args)
  end

  def read_c_comment(*args)
    @stream.read_c_comment(*args)
  end

  def read_newline(*args)
    @stream.read_newline(*args)
  end

  def read_classvar(*args)
    @stream.read_classvar(*args)
  end

  def clone
    substream = @stream.clone
    ret = self.class.new(substream)
    ret
  end

  def merge!(other_context, _ = nil)
    @stream.merge!(other_context.stream)
  end

  def on_subcontext(merge_local_vars: true)
    subcontext = self.clone
    ret = yield(subcontext)
    if ret
      merge!(subcontext, merge_local_vars)
    end
    ret
  end

  def __read_list(item_method, separator, init_value, accept_extra_separator: false)
    separator = [separator] unless separator.is_a? Array
    on_subcontext do |subcontext|
      ret = init_value

      next unless arg = subcontext.send(item_method)
      yield(ret, arg)

      while true
        if accept_extra_separator
          break unless sep = subcontext.read_any_operator(separator)
          break unless next_arg = subcontext.send(item_method)
          yield(ret, next_arg, sep)
        else
          next_item = subcontext.on_subcontext do |subsubcontext|
            next unless sep = subsubcontext.read_any_operator(separator)
            next unless next_arg = subsubcontext.send(item_method)
            yield(ret, next_arg, sep)
          end
          break unless next_item
        end
      end

      ret
    end
  end
end
