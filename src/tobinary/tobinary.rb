require_relative '../shared/debug_output.rb'
require_relative '../shared/opcodes.rb'

class InputStream
  attr_reader :lines

  def initialize
    @lines = STDIN.read.split("\n").map { |line| map_line(line) }
    errap @lines
  end

  def map_line(line)
    label = nil
    if line.start_with? '/*'
      line = line[line.index('*/ ') + 3..-1]
    end
    if line[/(\w+)\s*:(.*)$/]
      label = $1.strip
      line = $2.strip
    end
    line = line.split(',')
    line[0] = line[0].strip
    line[1..-1] = map_args(line[0], line[1..-1])
    line.unshift(label)
    line
  end

  def map_args(call, args)
    if call == 'PUSH_CONSTANT' || call == 'CALL' || call == 'SET_VAR' || call == 'PUSH_VAR' || call == 'PUSH_ARG' || call == 'CONSTANT_NUMBER'
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
    @lines.each { |line| yield(line[1..-1], line[0]) }
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

  def _push_vlc(arg)
    len = arg.length
    if len < 255
      _push_uint8(len)
    else
      _push_uint8(255)
      _push_uint64(len)
    end
    _push(arg.to_s)
  end

  def write(line)
    code = OPCODES_REV[line[0]]
    raise 'unknown token' unless code

    _push_uint8(code[:opcode])

    opcode = code
    arg_specifiers = opcode[:args]
    arg_specifiers = [opcode[:arg]] unless arg_specifiers
    arg_specifiers.compact!

    arg_specifiers.each_with_index do |kind, index|
      arg = line[index + 1]
      raise "No arg#{index}" unless arg
      send("_push_#{kind}", arg)
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
      if line[0] == 'START_FUNCTION'
        @in_function = true
        @function_line = line.dup
        @function_string = StringIO.new
        @function_stream = OutputStream.new(@function_string)
      elsif line[0] == 'END_FUNCTION'
        @function_line[3] = @function_stream.code.length
        @output_stream.write(@function_line)
        @output_stream._push(@function_stream.code)

        @in_function = false
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
