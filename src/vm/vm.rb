require_relative '../shared/debug_output.rb'
require_relative '../shared/opcodes.rb'

class DabInputStream
  def initialize(stream = nil)
    @stream = stream || STDIN
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
    @stream.read(n)
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

  def read_vlc
    len = read_uint8
    if len == 255
      len = read_uint64
    end
    arg = _read(len)
    arg
  end

  def read_line
    opcode = read_uint8
    return nil unless opcode
    opcode = OPCODES[opcode]
    raise 'unknown op' unless opcode

    arg_specifiers = opcode[:args]
    arg_specifiers = [opcode[:arg]] unless arg_specifiers
    arg_specifiers.compact!

    args = []
    arg_specifiers.each do |kind|
      args << send("read_#{kind}")
    end

    if opcode[:name] == 'START_FUNCTION'
      args << _read(args[2])
    end

    [opcode[:name], *args]
  end

  def each
    while true
      *args = read_line
      break unless args
      yield(*args)
    end
  end
end

class DabIntFunction
  attr_reader :body
  attr_reader :n_local_vars

  def initialize(body, n_local_vars)
    @body = body
    @n_local_vars = n_local_vars
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
    @local_vars = []
  end

  def define_function(name, body, n_local_vars)
    errap ['define fun', name, body.length, body, n_local_vars]
    @functions[name] = DabIntFunction.new(body, n_local_vars)
  end

  def run
    errap @stream.read_preamble
    run_stream(@stream, [])
  end

  def run_stream(stream, fun_args)
    stream.each do |opcode, arg, arg2, arg3, arg4|
      break unless opcode
      errap ['opcode', opcode, [arg, arg2, arg3, arg4], 'constants:', @constants, 'stack', @stack, 'locals:', @local_vars]
      if opcode == 'START_FUNCTION'
        body = arg4
        define_function(arg, body, arg2)
      elsif opcode == 'CONSTANT_SYMBOL'
        @constants << arg.to_sym
      elsif opcode == 'CONSTANT_STRING'
        @constants << arg.to_s
      elsif opcode == 'PUSH_CONSTANT'
        @stack << @constants[arg]
      elsif opcode == 'CALL'
        data = @stack.pop(arg + 1)
        call_function(data[0].to_s, *data[1..-1])
      elsif opcode == 'SET_VAR'
        value = @stack.pop
        define_local_variable(arg, value)
      elsif opcode == 'VAR'
        get_local_variable(arg)
      elsif opcode == 'ARG'
        @stack << fun_args[arg]
      else
        raise 'unknown opcode'
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
    @local_vars = []
    body = @functions[name]
    if body.is_a? DabIntFunction
      @local_vars = [nil] * body.n_local_vars
      execute(body.body, args)
    else
      errap ['Kernel.send(name.to_sym -> ' + name.to_sym.to_s + ', *args -> ' + args.to_s]
      Kernel.send(name.to_sym, *args)
    end
  end

  def execute(binary, args)
    stream = StringIO.new(binary)
    stream = DabInputStream.new(stream)
    run_stream(stream, args)
  end
end

stream = DabInputStream.new
vm = DabVM.new(stream)
vm.run
vm.call_function('main')
