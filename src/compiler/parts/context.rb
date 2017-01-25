class DabContext
  attr_reader :stream
  attr_accessor :local_vars

  def initialize(stream)
    @stream = stream
    @local_vars = []
  end

  def add_local_var(id)
    @local_vars << id
  end

  def read_program
    ret = DabNodeCodeBlock.new
    until @stream.eof?
      ret.insert(read_function)
      @stream.skip_whitespace
    end
    ret
  end

  def read_function
    on_subcontext do |subcontext|
      next false unless subcontext.read_keyword('func')
      ident = subcontext.read_identifier
      next false unless ident
      lparen = subcontext.read_operator('(')
      next false unless lparen
      rparen = subcontext.read_operator(')')
      next false unless rparen
      code = subcontext.read_codeblock
      next false unless code
      DabNodeFunction.new(ident, code)
    end
  end

  def read_identifier(*args)
    @stream.read_identifier(*args)
  end

  def read_operator(*args)
    @stream.read_operator(*args)
  end

  def read_string(*args)
    @stream.read_string(*args)
  end

  def read_keyword(*args)
    @stream.read_keyword(*args)
  end

  def read_instruction
    read_var || read_call
  end

  def read_local_var
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      if @local_vars.include? id
        DabNodeLocalVar.new(id)
      else
        false
      end
    end
  end

  def read_var
    on_subcontext do |subcontext|
      vark = subcontext.read_keyword('var')
      next false unless vark
      id = subcontext.read_identifier
      next false unless id
      eq = subcontext.read_operator('=')
      next false unless eq
      value = subcontext.read_value
      next false unless value

      subcontext.add_local_var(id)
      DabNodeDefineLocalVar.new(id, value)
    end
  end

  def read_call
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      next false unless id
      next false unless subcontext.read_operator('(')
      value = subcontext.read_value

      next false unless subcontext.read_operator(')')
      DabNodeCall.new(id, value)
    end
  end

  def read_codeblock
    on_subcontext do |subcontext|
      next false unless subcontext.read_operator('{')
      ret = DabNodeCodeBlock.new
      while true
        instr = subcontext.read_instruction
        break unless instr
        next false unless subcontext.read_operator(';')
        ret.insert(instr)
      end
      next false unless subcontext.read_operator('}')
      ret
    end
  end

  def read_literal_value
    on_subcontext do |subcontext|
      str = subcontext.read_string
      next false unless str
      DabNodeLiteralString.new(str)
    end
  end

  def read_value
    read_literal_value || read_local_var
  end

  def clone
    substream = @stream.clone
    ret = DabContext.new(substream)
    ret.local_vars = @local_vars.clone
    ret
  end

  def merge!(other_context)
    @stream.merge!(other_context.stream)
    @local_vars = other_context.local_vars
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
