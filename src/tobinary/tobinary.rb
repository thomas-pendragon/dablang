require 'awesome_print'

require_relative '../shared/opcodes.rb'

def errn(str, *args)
  if args.count > 0
    str = sprintf(str, *args)
  end
  STDERR.print(str)
end

def err(str, *args)
  errn(str.to_s + "\n", *args)
end

def errap(arg)
  STDERR.puts arg.ai
end

class InputStream
  attr_reader :lines

  def initialize
    @lines = STDIN.read.split("\n").map { |line| map_line(line) }
    errap @lines
  end

  def map_line(line)
    if line.start_with? '/*'
      line = line[line.index('*/ ') + 3..-1]
    end
    line = line.split(',')
    line[0] = line[0].strip
    line[1..-1] = map_args(line[0], line[1..-1])
    line
  end

  def map_args(call, args)
    if call == 'PUSH_CONSTANT' || call == 'CALL' || call == 'SET_VAR' || call == 'VAR'
      return args.map(&:to_i)
    end
    if call == 'START_FUNCTION' || call == 'CONSTANT_SYMBOL'
      name = args[0].strip.to_sym
      n_local = args[1].to_i
      return [name, n_local]
    end
    if call == 'CONSTANT_STRING'
      return args.map(&:strip).map { |s| s[1..-2] }
    end
    args
  end

  def each
    @lines.each { |line| yield(line) }
  end
end

class OutputStream
  attr_reader :code

  def initialize(target = nil)
    @stream = target || STDOUT
    @preamble = []
    @code = ''
    @metadata_source = nil
  end

  def begin(metadata_source)
    @metadata_source = metadata_source
  end

  def write(line)
    code = OPCODES_REV[line[0]]
    raise 'unknown token' unless code

    _push_uint8(code[:opcode])
    if code[:arg] == :uint16
      raise 'no arg' unless line[1]
      _push_uint16(line[1])
    end
    if code[:arg] == :vlc
      errap line
      raise 'no arg' unless line[1]
      arg = line[1]
      len = arg.length
      if len < 255
        _push_uint8(len)
      else
        _push_uint8(255)
        _push_uint64(len)
      end
      _push(arg.to_s)
    end
    if code[:arg2] == :uint16
      raise 'no arg2' unless line[2]
      _push_uint16(line[2])
    end
    if code[:arg3] == :uint16
      raise 'no arg3' unless line[3]
      _push_uint16(line[3])
    end
  end

  def _push_uint8(value)
    @code += [value].pack('C')
  end

  def _push_uint16(value)
    @code += [value].pack('S')
  end

  def _push_uint64(value)
    @code += [value].pack('Q<')
  end

  def _push(arg)
    @code += arg
  end

  def write_uint64(value)
    _write([value].pack('Q<'))
  end

  def _write(data)
    @stream.print(data)
  end

  def finalize
    length = @code.length
    crc = 0

    _write('DAB')
    write_uint64(@metadata_source.compiler_version)
    write_uint64(@metadata_source.vm_version)
    write_uint64(length)
    write_uint64(crc)
    _write(@code)
  end
end

class Parser
  def initialize(input_stream, output_stream)
    @input_stream = input_stream
    @output_stream = output_stream
  end

  def compiler_version
    1
  end

  def vm_version
    1
  end

  def run!
    @output_stream.begin(self)
    @input_stream.each do |line|
      errap ['read line:', line]
      if line[0] == 'START_FUNCTION'
        @in_function = true
        @function_line = line.dup
        @function_string = StringIO.new
        @function_stream = OutputStream.new(@function_string)
      elsif line[0] == 'END_FUNCTION'
        @function_line[3] = @function_stream.code.length
        @output_stream.write(@function_line)
        @output_stream._push(@function_stream.code)

        @function_line = nil
        @function_string = nil
        @function_stream = nil
      elsif @in_function
        @function_stream.write(line)
      else
        @output_stream.write(line)
      end
    end
    @output_stream.finalize
  end
end

input = InputStream.new
output = OutputStream.new
parser = Parser.new(input, output)
parser.run!
