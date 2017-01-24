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
    if call == 'PUSH_CONSTANT' || call == 'CALL'
      return args.map(&:to_i)
    end
    if call == 'START_FUNCTION' || call == 'CONSTANT_SYMBOL'
      return args.map(&:strip).map(&:to_sym)
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
  def initialize
    @stream = STDOUT
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
      @output_stream.write(line)
    end
    @output_stream.finalize
  end
end

input = InputStream.new
output = OutputStream.new
parser = Parser.new(input, output)
parser.run!
