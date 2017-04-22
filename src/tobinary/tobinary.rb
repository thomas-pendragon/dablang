require_relative '../shared/debug_output.rb'
require_relative '../shared/opcodes.rb'
require_relative '../shared/parser.rb'
require_relative './asm_context.rb'
require_relative '../shared/args.rb'

$debug = $settings[:debug]

class InputStream
  attr_reader :lines

  def initialize(input = STDIN)
    @stream = DabParser.new(input.read, false)
    @context = DabAsmContext.new(@stream)
    @lines = @context.read_program
    errap @lines
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
    raise "unknown token (#{line[0]})" unless code

    _push_uint8(code[:opcode])

    opcode = code
    arg_specifiers = opcode[:args]
    arg_specifiers = [opcode[:arg]] unless arg_specifiers
    arg_specifiers.compact!

    arg_specifiers.each_with_index do |kind, index|
      arg = line[index + 1]
      raise "line = #{line} - No arg#{index}" unless arg
      send("_push_#{kind}", arg)
    end
  end

  def _push_fixnum(value, spec)
    raise TypeError.new("expected Fixnum, got #{value} (#{value.class})") unless value.is_a? Fixnum
    @code += [value].pack(spec)
  end

  def _push_uint8(value)
    _push_fixnum(value, 'C')
  end

  def _push_uint16(value)
    _push_fixnum(value, 'S')
  end

  def _push_int16(value)
    _push_fixnum(value, 's')
  end

  def _push_uint64(value)
    _push_fixnum(value, 'Q<')
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

  def pos
    @code.length
  end

  def _rewind(pos)
    @rewrite_pos = pos
  end

  def _rewrite_int16(value)
    data = [value].pack('s')
    @code = @code[0...@rewrite_pos] + data + @code[@rewrite_pos + 2..-1]
  end

  def fix_jumps(labels, jumps)
    # errap ['jumps:', jumps, 'labels:', labels]
    jumps.each do |jump|
      jump_pos = jump[0]
      jump_label = jump[1]

      _rewind(jump_pos + 1) # opcode is 1 byte
      diff = labels[jump_label] - jump_pos
      _rewrite_int16(diff)
    end
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

  def pos
    @output_stream.pos
  end

  def run!
    @label_positions = {}
    @jump_corrections = []
    @output_stream.begin(self)
    @input_stream.each do |instr|
      errap instr
      line = [instr[:op]] + (instr[:arglist] || [])
      errap line
      label = instr[:label]
      next if line[0] == '' || line[0].nil?
      if line[0] == 'LOAD_FUNCTION' || line[0].start_with?('JMP')
        @jump_corrections << [pos, line[1].to_s]
        line[1] = 0
      end
      if label
        @label_positions[label.to_s] = pos
      end
      @output_stream.write(line)
    end
    @output_stream.fix_jumps(@label_positions, @jump_corrections)
    @output_stream.finalize
  end
end

input = InputStream.new
output = OutputStream.new
parser = Parser.new(input, output)
parser.run!
