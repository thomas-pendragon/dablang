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

class DabInputStream
  def initialize(stream = nil)
    @stream = stream || STDIN
    @function_cache = ''
  end

  def read_preamble
    {
      dab_mark: _read(3),
      compiler_version: read_uint64,
      vm_version: read_uint64,
      code_length: read_uint64,
      code_crc: read_uint64,
    }
  end

  def _read(n)
    return nil if @stream.eof?
    ret = @stream.read(n)
    @function_cache += ret
    ret
  end

  def read_uint8
    _read(1).unpack('C')[0]
  rescue
    nil
  end

  def read_uint16
    _read(2).unpack('S<')[0]
  rescue
    nil
  end

  def read_uint64
    _read(8).unpack('Q<')[0]
  rescue
    nil
  end

  def read_line
    opcode = read_uint8
    return nil unless opcode
    opcode = OPCODES[opcode]
    raise 'unknown op' unless opcode

    arg = nil
    if opcode[:arg] == :uint16
      arg = read_uint16
    end
    if opcode[:arg] == :vlc
      len = read_uint8
      if len == 255
        len = read_uint64
      end
      arg = _read(len)
    end

    if opcode[:name] == 'START_FUNCTION'
      @function_cache = ''
    end
    if opcode[:name] == 'END_FUNCTION'
      arg = @function_cache[0..-2]
    end

    [opcode[:name], arg]
  end

  def each
    while true
      *args = read_line
      break unless args
      yield(*args)
    end
  end
end

class DabVM
  def initialize(stream)
    @stream = stream
    @in_function = false
    @function_name = nil

    @constants = []
    @stack = []
    @functions = {}
    @functions['print'] = :print
    @local_vars = {}
  end

  def define_function(name, body)
    errap ['define fun', name, body.length, body]
    @functions[name] = body
  end

  def run
    errap @stream.read_preamble
    run_stream(@stream)
  end

  def run_stream(stream)
    stream.each do |opcode, arg|
      break unless opcode
      if @in_function
        if opcode == 'END_FUNCTION'
          define_function(@function_name, arg)
          @in_function = false
        end
      else
        errap ['opcode', opcode, arg, 'constants:', @constants, 'stack', @stack]
        if opcode == 'START_FUNCTION'
          @in_function = true
          @function_name = arg
        elsif opcode == 'CONSTANT_SYMBOL'
          @constants << arg.to_sym
        elsif opcode == 'CONSTANT_STRING'
          @constants << arg.to_s
        elsif opcode == 'PUSH_CONSTANT'
          @stack << @constants[arg]
        elsif opcode == 'CALL'
          data = @stack.pop(arg + 1)
          call_function(data[0].to_s, *data[1..-1])
        elsif opcode == 'DEFINE_VAR'
          args = @stack.pop(2)
          define_local_variable(args[0], args[1])
        elsif opcode == 'VAR'
          get_local_variable(@stack.pop)
        else
          raise 'unknown opcode'
        end
      end
    end
  end

  def get_local_variable(name)
    @stack << @local_vars[name]
  end

  def define_local_variable(name, value)
    @local_vars[name] = value
  end

  def call_function(name, *args)
    errap ['call function', name, 'args', args]
    @constants = []
    @local_vars = {}
    body = @functions[name]
    if body.is_a? String
      execute(body)
    else
      errap ['Kernel.send(name.to_sym -> ' + name.to_sym.to_s + ', *args -> ' + args.to_s]
      Kernel.send(name.to_sym, *args)
    end
  end

  def execute(binary)
    stream = StringIO.new(binary)
    stream = DabInputStream.new(stream)
    run_stream(stream)
  end
end

stream = DabInputStream.new
vm = DabVM.new(stream)
vm.run
vm.call_function('main')
