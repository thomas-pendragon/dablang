require_relative '../../setup.rb'
require_relative '../shared/debug_output.rb'
require_relative '../shared/opcodes.rb'
require_relative '../shared/parser.rb'
require_relative '../shared/asm_context.rb'
require_relative '../shared/args.rb'
require_relative '../shared/system.rb'
require_relative '../compiler/_requires.rb'

$debug = $settings[:debug]

class InputStream
  attr_reader :lines

  def initialize(input)
    @stream = DabParser.new(input, false)
    @context = DabAsmContext.new(@stream, numeric_labels: true)
    @lines = @context.read_program
  end

  def each
    @lines.each { |line| yield(line) }
  end
end

class DecompiledFunction
  def initialize(func, funcbody)
    @name = func[:symbol]
    @body = DabNodeTreeBlock.new
    @fun = DabNodeFunction.new(@name, @body, DabNode.new, false)

    cmd = './bin/cdisasm --raw'
    ret = qsystem(cmd, input: funcbody, timeout: 10)[:stdout]

    @stream = InputStream.new(ret)
  end

  def process(line)
    errap ['line', line]
    args = line[:arglist]
    op = line[:op]

    case op
    when 'STACK_RESERVE'
      # empty
    when 'LOAD_NUMBER'
      id = args[0]
      value = args[1]
      value = DabNodeLiteralNumber.new(value)
      @body << DabNodeDefineLocalVar.new(id, value)
    when 'RETURN'
      id = args[0]
      var = DabNodeLocalVar.new(id)
      @body << DabNodeReturn.new(var)
    else
      errap line
      raise "unknown op #{op}"
    end
  end

  def run!(output)
    @stream.each do |line|
      process(line)
    end
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
    body = @input.read
    program = DabBinReader.new.parse_dab_binary(body)

    code = program[:header][:sections].detect { |section| section[:name] == 'code' }

    min_func = code[:address]
    max_func = min_func + code[:length]

    # codebody = body[min_func...max_func]

    program[:functions].each do |func|
      address = func[:address]
      funcbody = body[address...max_func]

      process_function!(func, funcbody)
    end
  end

  def process_function!(func, funcbody)
    DecompiledFunction.new(func, funcbody).run!(@output)
  end
end

input = STDIN
output = STDOUT
parser = Decompiler.new(input, output)
parser.run!
