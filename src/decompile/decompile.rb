require_relative '../../setup.rb'
require_relative '../shared/debug_output.rb'
require_relative '../shared/opcodes.rb'
require_relative '../shared/parser.rb'
require_relative '../shared/asm_context.rb'
require_relative '../shared/args.rb'
require_relative '../compiler/_requires.rb'

$debug = $settings[:debug]

class InputStream
  attr_reader :lines

  def initialize(input = STDIN)
    @stream = DabParser.new(input.read, false)
    @context = DabAsmContext.new(@stream, numeric_labels: true)
    @lines = @context.read_program
  end

  def each
    @lines.each { |line| yield(line) }
  end
end

class DecompiledFunction
  def initialize(input)
    info = input[:info]
    @name = info[1]
    @data = input[:data]
    @body = DabNodeTreeBlock.new
    @fun = DabNodeFunction.new(@name, @body, DabNode.new, false)
    @stack = []
  end

  def process(line)
    errap ['stack', @stack, 'line', line]
    args = line[:arglist]
    case line[:op]
    when 'PUSH_NUMBER'
      @stack << DabNodeLiteralNumber.new(args[0])
    when 'PUSH_STRING'
      @stack << DabNodeLiteralString.new(args[0])
    when 'PUSH_NIL'
      @stack << DabNodeLiteralNil.new
    when 'RETURN'
      @body << DabNodeReturn.new(@stack.pop)
    when 'PUSH_SYMBOL'
      @stack << args[0]
    when 'CALL'
      nargs = args[0]
      id = @stack.pop
      arglist = @stack.pop(nargs)
      @stack << if %w{+}.include?(id)
                  DabNodeOperator.new(arglist[0], arglist[1], id)
                else
                  DabNodeCall.new(id, arglist)
                end
    when 'YIELD'
      nargs = args[0]
      arglist = @stack.pop(nargs)
      @body << DabNodeYield.new(arglist)
    else
      errap line
      raise 'unknown op'
    end
  end

  def run!(output)
    process(@data.shift) until @data.empty?
    options = {}
    @fun.dump
    output << @fun.formatted_source(options)
  end
end

class Decompiler
  def initialize(input, output)
    @input = input
    @output = output
    @functions = []
    @func = nil
  end

  def run!
    @input.each do |line|
      if line[:op] == 'LOAD_FUNCTION'
        func = line[:arglist]
        @functions << {info: func, pos: func[0], data: []}
      elsif line[:op] == 'BREAK_LOAD'
      elsif line[:op] == 'STACK_RESERVE'
        @func = @functions.detect { |f| f[:pos] == line[:label] }
      else
        @func[:data] << line
      end
    end
    @functions.each do |fun|
      process_function!(fun)
    end
  end

  def process_function!(fun)
    DecompiledFunction.new(fun).run!(@output)
  end
end

input = InputStream.new
output = STDOUT
parser = Decompiler.new(input, output)
parser.run!
