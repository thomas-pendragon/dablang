def errn(str, *args)
  if args.count > 0
    str = sprintf(str, *args)
  end
  STDERR.print(str)
end

def err(str, *args)
  errn(str + "\n", *args)
end

class DabProgramStream
  attr_reader :position

  def initialize(content)
    @content = content.freeze
    @position = 0
    @length = @content.length
  end

  def eof?
    @position == @length
  end

  def merge!(substream)
    @position = substream.position
  end

  def debug(info = '')
    STDERR.printf("[%-32s] pos %5d next: [%s]\n", info, @position, safe_lookup(32))
  end

  def safe_lookup(n)
    ret = lookup(n).gsub(/[\n\r\t]/, '.')
    ret += '.' while ret.length < n
    ret
  end

  def lookup(n = 1)
    @content[@position...(@position + n)]
  end

  def read_keyword(keyword)
    debug("keyword #{keyword} ?")
    skip_whitespace
    return false unless input_match(keyword)
    advance!(keyword.length)
    return false unless current_char_whitespace?
    advance!
    debug("keyword #{keyword} ok")
    true
  end

  def read_identifier
    debug('identifier ?')
    skip_whitespace
    ret = ''
    while current_char_identifier?
      ret += current_char
      advance!
    end
    skip_whitespace
    unless ret.empty?
      debug('identifier ok')
      ret
    end
  end

  def read_operator(operator)
    debug("operator #{operator} ?")
    skip_whitespace
    return false unless input_match(operator)
    advance!(operator.length)
    debug("operator #{operator} ok")
    true
  end

  def read_string
    debug('string ?')
    skip_whitespace
    return false unless input_match('"')
    advance!
    ret = ''
    until input_match('"')
      break unless current_char
      ret += current_char
      advance!
    end
    return false unless input_match('"')
    advance!
    debug('string ok')
    ret
  end

  def input_match(word)
    for i in 0...word.length do
      return false if current_char(i) != word[i]
    end
    true
  end

  def skip_whitespace
    advance! while current_char_whitespace?
  end

  def current_char_whitespace?
    current_char == ' ' || current_char == "\t" || current_char == "\r" || current_char == "\n"
  end

  def current_char_identifier?
    current_char =~ /[a-z]/
  end

  def current_char(offset = 0)
    @content[@position + offset]
  end

  def advance!(length = 1)
    @position += length
  end
end

require_relative 'nodes/node.rb'
require_relative 'nodes/node_call.rb'
require_relative 'nodes/node_code_block.rb'
require_relative 'nodes/node_constant.rb'
require_relative 'nodes/node_constant_reference.rb'
require_relative 'nodes/node_define_local_var.rb'
require_relative 'nodes/node_function.rb'
require_relative 'nodes/node_literal.rb'
require_relative 'nodes/node_literal_string.rb'
require_relative 'nodes/node_local_var.rb'
require_relative 'nodes/node_symbol.rb'

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

class DabCompiler
  def initialize(stream)
    @stream = stream
  end

  def program
    context = DabContext.new(@stream)
    context.read_program
  end
end

class DabPPFixLiterals
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      function.visit_all_and_replace(DabNodeLiteral) do |literal|
        if literal.parent.is_a? DabNodeConstant
          literal
        else
          function.add_constant(literal)
        end
      end
    end
  end
end

class DabPPFixLocalvars
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      local_vars = {}
      function.visit_all(DabNodeDefineLocalVar) do |node|
        node.index = local_vars.count
        local_vars[node.real_identifier] = node.index
      end
      function.visit_all(DabNodeLocalVar) do |node|
        node.index = local_vars[node.real_identifier]
      end
      function.n_local_vars = local_vars.count
    end
  end
end

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

stream = DabProgramStream.new(STDIN.read)
compiler = DabCompiler.new(stream)
program = compiler.program

DabPPFixLiterals.new.run(program)
DabPPFixLocalvars.new.run(program)

program.dump

output = DabOutput.new
program.compile(output)
