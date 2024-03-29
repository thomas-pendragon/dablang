require_relative '../../setup'
require_relative '../shared/debug_output'
require_relative '../shared/opcodes'
require_relative '../shared/parser'
require_relative '../shared/asm_context'
require_relative '../shared/args'
require_relative '../shared/system'
require_relative '../compiler/_requires'

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
  def initialize(func, funcbody, dabbody, dab, klass)
    @name = func[:symbol]
    @real_body = DabNodeTreeBlock.new
    @arglist = DabNode.new
    @fun = DabNodeFunction.new(@name, @real_body, @arglist, false)

    cmd = './bin/cdisasm --raw'
    ret = qsystem(cmd, input: funcbody, timeout: 10, binmode: true)[:stdout]

    @stream = InputStream.new(ret)
    @dabbody = dabbody
    @dab = dab
    @klass = klass
  end

  def _get_data(address, length)
    @dabbody[address...(address + length)]
  end

  def process(line)
    errap ['line', line]
    args = line[:arglist]
    op = line[:op]
    @body = @blocks[line[:label]]

    case op
    when 'STACK_RESERVE'
      # empty
    when 'LOAD_NUMBER'
      value = args[1]
      value = DabNodeLiteralNumber.new(value)
      _define_var(args[0], value)
    when 'LOAD_STRING'
      value = _get_data(args[1], args[2])
      value = DabNodeLiteralString.new(value)
      _define_var(args[0], value)
    when 'LOAD_TRUE'
      value = DabNodeLiteralBoolean.new(true)
      _define_var(args[0], value)
    when 'LOAD_FALSE'
      value = DabNodeLiteralBoolean.new(false)
      _define_var(args[0], value)
    when 'LOAD_CLASS'
      id = _klass(args[1])
      value = DabNodeClass.new(id)
      _define_var(args[0], value)
    when 'NEW_ARRAY'
      values = args[1..-1].map do |reg|
        DabNodeLocalVar.new(reg)
      end
      value = DabNodeLiteralArray.new(values)
      _define_var(args[0], value)
    when 'LOAD_ARG'
      index = args[1]
      _bump_args(index + 1)
      value = DabNodeArg.new(index, nil)
      _define_var(args[0], value)
    when 'LOAD_ARG_DEFAULT'
      index = args[1]
      defvalue = args[2]
      setter = @blocks
               .values
               .flat_map { |block| block.all_nodes(DabNodeDefineLocalVar) }
               .detect { |node| node.identifier == defvalue }
      raise 'no setter' unless setter

      _bump_args(index + 1, setter.value)
      setter.remove!
      value = DabNodeArg.new(index, nil)
      _define_var(args[0], value)
    when 'RETURN'
      id = args[0]
      var = if id == 'RNIL'
              DabNodeLiteralNil.new
            else
              DabNodeLocalVar.new(id)
            end
      @body << DabNodeReturn.new(var)
    when 'CALL'
      symbol = _symbol(args[1])
      callargs = _get_args(args[2..-1])
      call = DabNodeCall.new(symbol, callargs, nil)
      _define_var(args[0], call)
    when 'INSTCALL'
      symbol = _symbol(args[2])
      value = DabNodeLocalVar.new(args[1])
      callargs = _get_args(args[3..-1])
      call = if ['+', '-', '*', '/', '==', '>', '<', '>=', '<=', '!='].include?(symbol) && (callargs.count == 1)
               DabNodeOperator.new(value, callargs[0], symbol)
             else
               DabNodeInstanceCall.new(value, symbol, callargs, nil)
             end
      _define_var(args[0], call)
    when 'SYSCALL'
      syscall = args[1]
      callargs = _get_args(args[2..-1])
      syscall = DabNodeSyscall.new(syscall, callargs)
      _define_var(args[0], syscall)
    when 'JMP_IF'
      reg = DabNodeLocalVar.new(args[0])
      pos1 = args[1] + line[:label]
      pos2 = args[2] + line[:label]
      @body << DabNodeConditionalJump.new(reg, @blocks[pos1], @blocks[pos2])
    when 'JMP'
      pos = args[0] + line[:label]
      @body << DabNodeJump.new(@blocks[pos])
    when 'NOP'
    when 'LOAD_SELF'
      _define_var(args[0], DabNodeSelf.new)
    when 'LOAD_LOCAL_BLOCK'
      _define_var(args[0], DabNodeCall.new('__localblock', [DabNodeLocalVar.new(args[1])], nil))
    when 'GET_INSTVAR'
      _define_var(args[0], DabNodeInstanceVar.new("@#{_symbol(args[1])}"))
    when 'GET_INSTVAR_EXT'
      _define_var(args[0], DabNodeInstanceVarProxy.new(DabNodeLocalVar.new(args[2]), _symbol(args[1])))
    when 'UNBOX'
      _define_var(args[0], DabNodeCall.new('__unbox', [DabNodeLocalVar.new(args[1])], nil))
    when 'BOX'
      _define_var(args[0], DabNodeCall.new('__box', [DabNodeLocalVar.new(args[1])], nil))
    when 'LOAD_CURRENT_BLOCK'
      _define_var(args[0], DabNodeCall.new('__current_block', [], nil))
    when 'SET_INSTVAR'
      symbol = _symbol(args[0])
      data = DabNodeLocalVar.new(args[1])
      @body << DabNodeSetInstVar.new("@#{symbol}", data)
    else
      errap line
      raise "unknown op #{op}"
    end
  end

  def _get_args(args)
    args.map do |arg|
      DabNodeLocalVar.new(arg)
    end
  end

  def _bump_args(count, def_value = nil)
    while @arglist.count < count
      index = @arglist.count
      @arglist << DabNodeArgDefinition.new(index, "arg#{index}", nil, def_value)
    end
  end

  def _symbol(symbol)
    symbol = symbol.delete('S').to_i
    @dab[:symbols][symbol]
  end

  def _klass(klass)
    return nil if klass == 65535
    if klass >= USER_CLASSES_OFFSET
      return @dab[:klasses].detect { |data| data[:index] == klass }[:symbol]
    end

    STANDARD_CLASSES[klass]
  end

  def _define_var(id, value)
    @body << if id == 'RNIL'
               value
             else
               DabNodeDefineLocalVar.new(id, value)
             end
  end

  def run!(output)
    @blocks = {}
    @stream.each do |line|
      node = DabNodeBasicBlock.new
      @blocks[line[:label]] = node
      @real_body << node
    end

    @stream.each do |line|
      process(line)
    end

    @blocks.each_value do |value|
      value.remove! if value.empty?
    end

    options = {skip_unused_labels: true}

    @fun.dump

    postprocess!(@fun)

    @fun.dump

    if @klass
      # TODO: parent classes
      @fun = DabNodeClassDefinition.new(@klass, nil, [@fun])
    end

    output << @fun.formatted_source(options)
    output << "\n"
  end

  def postprocess!(fun)
    while true
      next if PostprocessDecompiled.new.run(fun)
      next if DecompileIfs.new.run(fun)
      next if DecompileElseIfs.new.run(fun)
      next if ReplaceSingleUse.new.run(fun)

      break
    end
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
    @input.binmode
    body = @input.read
    program = DabBinReader.new.parse_dab_binary(body)

    code = program[:header][:sections].detect { |section| section[:name] == 'code' }

    min_func = code[:address]
    max_func = min_func + code[:length]

    functions = program[:functions].sort_by { |func| func[:address] }

    functions.each_with_index do |func, index|
      next_func = functions[index + 1]
      func[:end_address] = next_func&.[](:address) || max_func
    end

    program[:functions].each do |func|
      klass = func[:klass]

      address = func[:address]
      end_address = func[:end_address]
      funcbody = body[address...end_address]

      process_function!(func, funcbody, body, program, klass)
    end
  end

  def process_function!(*args)
    DecompiledFunction.new(*args).run!(@output)
  end
end

input = STDIN
output = STDOUT
parser = Decompiler.new(input, output)
parser.run!
