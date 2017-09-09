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
      {name: 'PUSH_NIL'}, # push(1)
      {name: 'PUSH_SELF'}, # push(1)
      {name: 'PUSH_TRUE'}, # push(1)
      {name: 'PUSH_FALSE'}, # push(1)
      {name: 'PUSH_STRING', args: %i{vlc}}, # push(1)
      {name: 'PUSH_NUMBER', args: %i{uint64}}, # push(1)
      {name: 'PUSH_NUMBER_UINT8', args: %i{uint8}}, # push(1)
      {name: 'PUSH_NUMBER_INT32', args: %i{int32}}, # push(1)
      {name: 'PUSH_NUMBER_UINT32', args: %i{uint32}}, # push(1)
      {name: 'PUSH_NUMBER_UINT64', args: %i{uint64}}, # push(1)
      {name: 'PUSH_ARRAY', args: %i{uint16}}, # pop(arg), push(1)
      {name: 'PUSH_CLASS', args: %i{uint16}}, # push(1)
      {name: 'PUSH_CONSTANT', args: %i{uint16}}, # constant index, push(1)
      {name: 'PUSH_ARG', args: %i{uint16}}, # argument index, push(1)
      {name: 'PUSH_INSTVAR', args: %i{vlc}}, # push(1)
      {name: 'PUSH_SYMBOL', args: %i{vlc}}, # push(1)
      {name: 'PUSH_HAS_BLOCK'}, # push(1)
      {name: 'PUSH_METHOD', args: %i{vlc}}, # arg0 = name, push(1)
      {name: 'PUSH_SSA', args: %i[reg]}, # stack <- reg(arg0); push(1)
    ],
  },
  {
    group: 'STACK OTHER',
    items:
    [
      {name: 'POP', args: %i{uint16}}, # pop(n)
      {name: 'DUP'}, # push(1)
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
      {name: 'CALL', args: %i(uint16)}, # n = number of arguments, pop(n + 1), push(1)
      {name: 'CALL_BLOCK', args: %i(uint16)}, # n = number of arguments, pop(n + 2), push(1)
      {name: 'INSTCALL', args: %i(uint16)}, # n = number of arguments, pop(n + 2), push(1)
      {name: 'INSTCALL_BLOCK', args: %i(uint16)}, # n = number of arguments, pop(n + 3), push(1)
      {name: 'HARDCALL', args: %i(uint16)}, # n = number of arguments, pop(n + 1), push(1)
      {name: 'HARDCALL_BLOCK', args: %i(uint16)}, # n = number of arguments, pop(n + 2), push(1)
      {name: 'SYSCALL', args: %i{uint8}}, # depends on the call
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
      {name: 'JMP_IF2', args: %i[int16 int16]}, # pop(1), add +arg1/2 to PC depending on stack value
      {name: 'RETURN'}, # pop(1)
      {name: 'YIELD', args: %i{uint16}}, # n = number of args, pop(n)
    ],
  },
  {
    group: 'VARIABLES',
    items:
    [
      {name: 'SET_INSTVAR', args: %i{vlc}}, # pop(1)
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
      {name: 'Q_SET_CALL_STACK', args: %i[reg symbol uint16]}, # reg(arg0) <- call(symbol(arg1), stack), pop(arg2)
      {name: 'Q_SET_SYSCALL_STACK', args: %i[reg uint8]}, # reg(arg0) <- syscall(arg1, stack), pop(variable)
      {name: 'Q_SET_SYSCALL', args: %i[reg uint8 reglist]}, # reg(arg0) <- syscall(arg1, arg2...argn)
      {name: 'Q_SET_REG', args: %i[reg reg]}, # reg(arg0) <- reg(arg1)
      {name: 'Q_SET_CLOSURE', args: %i[reg uint16]}, # reg(arg0) <- closurevar(arg1)
    ],
  },
  {
    group: 'REGISTER-BASED OPCODES - OTHER',
    items:
    [
      {name: 'Q_VOID_SYSCALL', args: %i[uint8 reglist]}, # syscall(arg1, arg2...argn)
      {name: 'Q_RELEASE', args: %i{reg}}, # release(reg(arg0))
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

STANDARD_CLASSES = %w(
  Object
  String
  LiteralString
  Fixnum
  LiteralFixnum
  Boolean
  NilClass
  Array
  Uint8
  Int32
  Method
  Uint64
  Uint32
  IntPtr
  ByteBuffer
).freeze

STANDARD_CLASSES_REV = STANDARD_CLASSES.each_with_index.map { |item, index| [item, index] }.to_h

USER_CLASSES_OFFSET = 0x100

REFLECTION = {
  0x00 => :method_arguments,
  0x01 => :method_argument_names,
}.freeze

REFLECTION_REV = REFLECTION.map { |k, v| [v, k] }.to_h
