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

  def clone
    substream = @stream.clone
    ret = DabContext.new(substream)
    ret
  end

  def merge!(other_context)
    @stream.merge!(other_context.stream)
  end

  def on_subcontext
    subcontext = self.clone
    ret = yield(subcontext)
    if ret
      merge!(subcontext)
    end
    ret
  end

  def __read_list(item_method, separator, init_value)
    separator = [separator] unless separator.is_a? Array
    on_subcontext do |subcontext|
      ret = init_value

      next false unless arg = subcontext.send(item_method)
      yield(ret, arg)

      while true
        next_item = subcontext.on_subcontext do |subsubcontext|
          next false unless sep = subsubcontext.read_any_operator(separator)
          next false unless next_arg = subsubcontext.send(item_method)
          yield(ret, next_arg, sep)
        end
        break unless next_item
      end

      ret
    end
  end
end
