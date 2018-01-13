require_relative '../../setup.rb'
require_relative '../shared/debug_output.rb'
require_relative '../shared/opcodes.rb'
require_relative '../shared/parser.rb'
require_relative '../shared/asm_context.rb'
require_relative '../shared/args_noautorun.rb'

$autorun = true if $autorun.nil?

class InputStream
  attr_reader :lines

  def initialize(input = STDIN)
    @stream = DabParser.new(input.read, false)
    @context = DabAsmContext.new(@stream)
    @lines = @context.read_program
    errap @lines if debug?
  end

  def debug?
    $debug
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
    @header_length = 0
  end

  def debug?
    $debug
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

  def _push_reg(arg)
    val = if arg == 'RNIL'
            0xFFFF
          else
            arg.delete('R').to_i
          end
    _push_int16(val)
  end

  def _push_reglist(args)
    _push_uint8(args.count)
    args.each do |arg|
      _push_reg(arg)
    end
  end

  def _push_symbol(arg)
    val = if arg == 'S_NOTEQ'
            11 # hack
          elsif arg == 'S_EQ'
            6 # hack
          else
            arg.delete('S').to_i
          end
    _push_uint16(val)
  end

  def _push_string4(arg)
    str = sprintf('%-4s', arg)[0..4]
    _push(str)
  end

  def _push_cstring(str)
    _push(str)
    _push_uint8(0)
  end

  def write(line)
    code = OPCODES_REV[line[0]]
    raise "unknown token (#{line[0]})" unless code

    _push_uint8(code[:opcode])

    opcode = code
    arg_specifiers = opcode[:args] || []

    errap ['arg_specifiers', arg_specifiers] if debug?

    arg_specifiers.each_with_index do |kind, index|
      reglist = kind == :reglist
      arg = if reglist
              line[(index + 1)..-1]
            else
              line[index + 1]
            end
      raise "line = #{line} - No arg#{index}" unless arg
      send("_push_#{kind}", arg)
      break if reglist
    end
  end

  def _push_fixnum(value, spec)
    raise TypeError.new("expected Integer, got #{value} (#{value.class})") unless value.is_a? Integer
    @code += [value].pack(spec)
  end

  def _push_uint8(value)
    _push_fixnum(value, 'C')
  end

  def _push_int8(value)
    _push_fixnum(value, 'c')
  end

  def _push_uint16(value)
    _push_fixnum(value, 'S')
  end

  def _push_int16(value)
    _push_fixnum(value, 's')
  end

  def _push_int32(value)
    _push_fixnum(value, 'l<')
  end

  def _push_uint32(value)
    _push_fixnum(value, 'L<')
  end

  def _push_uint64(value)
    _push_fixnum(value, 'Q<')
  end

  def _push_int64(value)
    _push_fixnum(value, 'q<')
  end

  def _push(arg)
    @code += arg
  end

  def write_string4(arg)
    str = sprintf('%-4s', arg)[0...4]
    _write(str)
  end

  def write_uint8(value)
    _write([value].pack('C'))
  end

  def write_uint32(value)
    _write([value].pack('L<'))
  end

  def write_uint64(value)
    _write([value].pack('Q<'))
  end

  def _write(data)
    @stream.print(data)
  end

  def finalize_newformat(raw, version, offset, sections, labels)
    unless raw
      _write('DAB')
      write_uint8(0)

      write_uint32(version)

      write_uint64(offset)

      size_of_header = 4 + 4 + 8 + 8 + 8 + 8 + sections.count * 32
      size_of_data = @code.length - size_of_header

      write_uint64(size_of_header)
      write_uint64(size_of_data)
      write_uint64(sections.count)

      sections.each do |section|
        section[:address] = labels[section[:label]]
      end

      sections.sort_by! do |section|
        section[:address]
      end

      sections.each_with_index do |section, index|
        next_section = sections[index + 1]
        next_address = if next_section
                         next_section[:address]
                       else
                         size_of_data + size_of_header
                       end
        section[:length] = next_address - section[:address]
      end

      sections.each do |section|
        write_string4(section[:name])
        write_uint32(0)
        write_uint32(0)
        write_uint32(0)
        write_uint64(section[:address])
        write_uint64(section[:length])
      end
    end

    _write(@code[@header_length..-1])
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

  def fix_jumps(labels, jumps, offset)
    jumps.each do |jump|
      jump_pos = jump[0]
      jump_label = jump[1]

      _rewind(jump_pos + 1 + offset * 2) # opcode is 1 byte
      diff = labels[jump_label] - jump_pos
      _rewrite_int16(diff)
    end
  end

  def push_header(length)
    @header_length = length
    _push(' ' * @header_length)
  end
end

class Parser
  def initialize(input_stream, output_stream)
    @input_stream = input_stream
    @output_stream = output_stream
  end

  def debug?
    $debug
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

  def print_temp_header!(sections_count)
    header_length = 40 + 32 * sections_count
    @output_stream.push_header(header_length)
  end

  def _process(item)
    case item
    when Hash
      left = _process(item[:left])
      right = _process(item[:right])
      raise '?' unless item[:op] == '+'
      left + right
    when String
      @label_positions[item]
    when Fixnum
      item
    else
      raise "unknown item #{item.class}"
    end
  end

  def _process_address(item)
    @header_offset + _process(item)
  end

  def run!(raw)
    @sections = []
    @header_version = nil
    @header_finished = false
    @header_offset = 0

    @label_positions = {}
    @jump_corrections = []
    @jump_corrections2 = []
    @jump_corrections3 = []
    @output_stream.begin(self)
    @input_stream.each do |instr|
      errap instr if debug?
      line = [instr[:op]] + (instr[:arglist] || [])
      errap line if debug?
      label = instr[:label]
      if label
        @label_positions[label.to_s] = pos
      end
      next if line[0] == '' || line[0].nil?
      if line[0].start_with?('W_')
        case line[0]
        when 'W_HEADER'
          @header_version = line[1].to_i
        when 'W_OFFSET'
          @header_offset = line[1].to_i
        when 'W_SECTION'
          @sections << {name: line[2].to_s, label: line[1].to_s}
        when 'W_END_HEADER'
          @header_finished = true
          print_temp_header!(@sections.count)
        when 'W_STRING'
          @output_stream._push_cstring(line[1])
        when 'W_SYMBOL'
          @output_stream._push_uint64(_process(line[1]))
        when 'W_METHOD'
          @output_stream._push_uint16(line[1])
          @output_stream._push_uint16(line[2])
          @output_stream._push_uint64(_process_address(line[3]))
        when 'W_CLASS'
          @output_stream._push_uint16(line[1])
          @output_stream._push_uint16(line[2])
          @output_stream._push_uint16(line[3])
        when 'W_METHOD_EX'
          @output_stream._push_uint16(line[1])
          @output_stream._push_uint16(line[2])
          @output_stream._push_uint64(_process_address(line[3]))
          @output_stream._push_uint16(line[4])
        when 'W_METHOD_ARG'
          @output_stream._push_uint16(line[1])
          @output_stream._push_uint16(line[2])
        when 'W_COV_FILE'
          @output_stream._push_uint64(_process(line[1]))
        when 'W_BYTE'
          @output_stream._push_uint8(line[1])
        else
          raise 'unknown W_ op'
        end
      else
        raise 'header not finished yet' if !raw && !@header_finished
        if line[0] == 'JMP_IF'
          @jump_corrections2 << [pos, line[2].to_s]
          @jump_corrections3 << [pos, line[3].to_s]
          line[2] = 0
          line[3] = 0
        elsif line[0].start_with?('JMP')
          @jump_corrections << [pos, line[1].to_s]
          line[1] = 0
        end
        if line[0] == 'LOAD_STRING'
          line[2] = _process(line[2])
        end
        @output_stream.write(line)
      end
    end
    @output_stream.fix_jumps(@label_positions, @jump_corrections, 0)
    @output_stream.fix_jumps(@label_positions, @jump_corrections2, 1)
    @output_stream.fix_jumps(@label_positions, @jump_corrections3, 2)
    @output_stream.finalize_newformat(raw, @header_version, @header_offset, @sections, @label_positions)
  end
end

def run_tobinary(input, output, debug, _newformat, raw)
  $debug = debug
  input = InputStream.new(input)
  output = OutputStream.new(output)
  parser = Parser.new(input, output)
  parser.run!(raw)
end

if $autorun
  read_args!
  debug = $settings[:debug]
  raw = $settings[:raw]
  run_tobinary(STDIN, STDOUT, debug, true, raw)
end
