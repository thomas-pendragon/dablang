# VARIABLE LENGTH CODING

# 0-254 - direct
# 255 -> +8 bytes of length

# [250] [250 bytes]

# [255] [64bits: length = 1000] [1000 bytes]

# VM FORMAT

# all binary numbers are little endian

# "DAB"
# 8 bytes: compiler version
# 8 bytes: vm version
# 8 bytes: code length
# 8 bytes: code crc32

OPCODES_ARRAY_BASE = [
  {
    group: 'NOP',
    items:
    [
      {name: 'NOP'}, #
    ],
  },
  {
    group: 'STACK PUSH',
    items:
    [
      {name: 'PUSH_CLASS', args: %i{uint16}}, # push(1)
      {name: 'PUSH_CONSTANT', args: %i{uint16}}, # constant index, push(1)
      {name: 'PUSH_ARG', args: %i{uint16}}, # argument index, push(1)
      {name: 'PUSH_INSTVAR'}, # pop(1), push(1)
      {name: 'PUSH_SYMBOL', args: %i{vlc}}, # push(1)
      {name: 'PUSH_METHOD', args: %i{vlc}}, # arg0 = name, push(1)
      {name: 'PUSH_SSA', args: %i[reg]}, # stack <- reg(arg0); push(1)
    ],
  },
  {
    group: 'STACK OTHER',
    items:
    [
      {name: 'POP', args: %i{uint16}}, # pop(n)
    ],
  },
  {
    group: 'CONSTANTS',
    items:
    [
      {name: 'CONSTANT_SYMBOL', args: %i{vlc}}, # symbol
      {name: 'CONSTANT_STRING', args: %i{vlc}}, # string
      {name: 'CONSTANT_NUMBER', args: %i{uint64}}, # number
    ],
  },
  {
    group: 'CALLS',
    items:
    [
      {name: 'CAST', args: [:uint16]}, # pop(1), push(1)
    ],
  },
  {
    group: 'FLOW',
    items:
    [
      {name: 'JMP', args: %i{int16}}, # add +arg to PC
      {name: 'JMP_IF', args: %i{int16}}, # pop(1), add +arg to PC if value from stack is true
      {name: 'JMP_IFN', args: %i{int16}}, # pop(1), add +arg to PC if value from stack is false
      {name: 'JMP_IF2', args: %i[int16 int16]}, # pop(1), add +arg0/1 to PC depending on stack value
      {name: 'Q_JMP_IF2', args: %i[reg int16 int16]}, # add +arg1/2 to PC depending on reg[arg0]
      {name: 'YIELD', args: %i{uint16}}, # n = number of args, pop(n)
    ],
  },
  {
    group: 'COVERAGE',
    items:
    [
      {name: 'COV_FILE', args: %i(uint16 vlc)}, # args: filehash, filename
      {name: 'COV', args: %i(uint16 uint16)}, # args: filehash, fileline
    ],
  },
  {
    group: 'OTHER',
    items:
    [
      {name: 'START_FUNCTION', args: %i(vlc uint16 uint16 uint16)}, # function name, class index (or -1), number of local variables, body length
      {name: 'LOAD_FUNCTION', args: %i(uint16 vlc uint16)}, # [address, name, classIndex]
      {name: 'STACK_RESERVE', args: [:uint16]}, # reserve space (for ie. local variables)
      {name: 'DEFINE_CLASS', args: %i(vlc uint16 uint16)}, # n = name, n2 = class index, n3 = base class index
      {name: 'BREAK_LOAD'}, # stop loading the code
      {name: 'REFLECT', args: %i{uint16}}, # pop symbol, arg0 = reflection type, pop(1), push(1)
      {name: 'DESCRIBE_FUNCTION', args: %i{vlc uint16}}, # arg0 = name, arg1 = number of arguments, pop(arg1*2 + 1) (argument types + return type)
    ],
  },
  {
    group: 'REGISTER-BASED OPCODES - SETTERS',
    items:
    [
      {name: 'Q_SET_CONSTANT', args: %i[reg int16]}, # reg(arg0) <- constant(arg1)
      {name: 'Q_SET_POP', args: %i[reg]}, # reg(arg0) <- stack; pop(1)
      {name: 'Q_SET_NUMBER', args: %i[reg uint64]}, # reg(arg0) <- arg1
      {name: 'Q_SET_ARG', args: %i[reg uint16]}, # reg(arg0) <- funarg(arg1)
      {name: 'Q_SET_CLASS', args: %i[reg uint16]}, # reg(arg0) <- class(arg1)
      {name: 'Q_SET_CALL', args: %i[reg symbol reglist]}, # reg(arg0) <- call(symbol(arg1), arg2..argn)
      {name: 'Q_SET_SYSCALL', args: %i[reg uint8 reglist]}, # reg(arg0) <- syscall(arg1, arg2...argn)
      {name: 'Q_SET_REG', args: %i[reg reg]}, # reg(arg0) <- reg(arg1)
      {name: 'Q_SET_CLOSURE', args: %i[reg uint16]}, # reg(arg0) <- closurevar(arg1)
      {name: 'Q_SET_NIL', args: %i[reg]}, # reg(arg0) <- nil
      {name: 'Q_SET_INSTCALL', args: %i[reg reg symbol reglist]}, # reg(arg0) <- call(symbol(arg2), self: arg1, args: arg3..argn)
      {name: 'Q_SET_CALL_BLOCK', args: %i[reg symbol symbol reg reglist]}, # reg(arg0) <- call(symbol(arg1), block=arg2, capture=arg3, arg4..argn)
      {name: 'Q_SET_TRUE', args: %i[reg]}, # reg(arg0) <- true
      {name: 'Q_SET_FALSE', args: %i[reg]}, # reg(arg0) <- false
      {name: 'Q_SET_INSTVAR', args: %i[reg symbol]}, # reg(arg0) <- self.@arg1
      {name: 'Q_SET_INSTCALL_BLOCK', args: %i[reg reg symbol symbol reg reglist]}, # reg(arg0) <- call(symbol(arg2), self: arg1, block: arg3, capture: arg4, args: arg5..argn)
    ],
  },
  {
    group: 'REGISTER-BASED OPCODES - OTHER',
    items:
    [
      {name: 'Q_RELEASE', args: %i{reg}}, # release(reg(arg0))
      {name: 'Q_CHANGE_INSTVAR', args: %i{symbol reg}}, # self.@arg0 <- reg(arg1)
      {name: 'Q_RETURN', args: %i[reg]}, # return(reg(arg0))
      {name: 'Q_RETAIN', args: %i{reg}}, # retain(reg(arg0))
      {name: 'Q_CAST', args: %i[reg reg uint16]}, # reg(arg0) = reg(arg1) as arg2
    ],
  },
  {
    group: 'REGISTER-BASED OPCODES - TYPED NUMBERS',
    items:
    [
      {name: 'Q_SET_NUMBER_INT32', args: %i{reg int32}}, # reg(arg0) = arg1
      {name: 'Q_SET_NUMBER_UINT8', args: %i{reg uint8}}, # reg(arg0) = arg1
      {name: 'Q_SET_NUMBER_UINT32', args: %i{reg uint32}}, # reg(arg0) = arg1
      {name: 'Q_SET_NUMBER_UINT64', args: %i{reg uint64}}, # reg(arg0) = arg1
    ],
  },
  {
    group: 'NEW',
    items:
    [
      {name: 'Q_SET_HAS_BLOCK', args: %i[reg]}, # reg(arg0) <- has_block?
      {name: 'Q_SET_NEW_ARRAY', args: %i[reg reglist]}, # reg(arg0) <- [reg(arg1), reg(arg2), ... reg(argn)]
      {name: 'Q_SET_SELF', args: %i[reg]}, # reg(arg0) <- self
      {name: 'Q_YIELD', args: %i[reglist]}, # yield(reg(arg0)..reg(argn))
      {name: 'W_HEADER', args: %i[uint16]}, # dump header, version number = arg0
      {name: 'W_SECTION', args: %i[uint16 string4]}, # header entry, address = arg0, label = arg1
      {name: 'W_END_HEADER'}, # finish header
    ],
  },
].freeze

OPCODES_ARRAY = OPCODES_ARRAY_BASE.flat_map { |item| item[:items] }

OPCODES = Hash[(0...OPCODES_ARRAY.size).zip OPCODES_ARRAY].freeze

OPCODES_REV = OPCODES.map { |k, v| [v[:name], v.merge(opcode: k)] }.to_h

KERNELCODES = {
  0x00 => 'PRINT',
  0x01 => 'EXIT',
  0x02 => 'USECOUNT', # 65535 if stack, 65536 if static
}.freeze

KERNELCODES_REV = KERNELCODES.map { |k, v| [v, k] }.to_h

require_relative './classes.rb'

REFLECTION = {
  0x00 => :method_arguments,
  0x01 => :method_argument_names,
}.freeze

REFLECTION_REV = REFLECTION.map { |k, v| [v, k] }.to_h
