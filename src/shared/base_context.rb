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
end
