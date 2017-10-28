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
    group: 'FLOW',
    items:
    [
      {name: 'JMP', args: %i{int16}}, # add +arg to PC
      {name: 'Q_JMP_IF2', args: %i[reg int16 int16]}, # add +arg1/2 to PC depending on reg[arg0]
    ],
  },
  {
    group: 'COVERAGE',
    items:
    [
      {name: 'COV', args: %i(uint16 uint16)}, # args: filehash, fileline
    ],
  },
  {
    group: 'OTHER',
    items:
    [
      {name: 'STACK_RESERVE', args: [:uint16]}, # reserve space (for ie. local variables)
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
      {name: 'W_STRING', args: %i[cstring]}, # raw data, zero byte limited
      {name: 'Q_SET_STRING', args: %i[reg uint64 uint64]}, # reg(arg0) <- string(*arg1, length = arg2)
      {name: 'W_SYMBOL', args: %i[uint64]}, # define symbol at address, zero-terminated
      {name: 'W_METHOD', args: %i[symbol uint16 uint64]}, # arg0 = symbol arg1 = class index arg2 = address
      {name: 'W_CLASS', args: %i[uint16 uint16 symbol]}, # arg0 = class index arg1 = parent class index arg2 = name
      {name: 'W_METHOD_EX', args: %i[symbol uint16 uint64 uint16]}, # arg0 = symbol arg1 = class index arg2 = address, arg3 = number of args (for reflection)
      {name: 'W_METHOD_ARG', args: %i[symbol uint16]}, # arg0 = name arg1 = type
      {name: 'Q_SET_REFLECT', args: %i[reg symbol uint16]}, # reg0 <- reflect(sym1) with type arg2
      {name: 'Q_SET_REFLECT2', args: %i[reg symbol uint16 uint16]}, # reg0 <- reflect(sym1) with type arg2, klass=arg3
      {name: 'W_COV_FILE', args: %i[uint64]}, # arg0 = cstr pointer
      {name: 'Q_SET_METHOD', args: %i[reg symbol]}, # reg0 <- method[sym1]
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
  0x03 => 'TO_SYM',
}.freeze

KERNELCODES_REV = KERNELCODES.map { |k, v| [v, k] }.to_h

require_relative './classes.rb'

REFLECTION = {
  0x00 => :method_arguments,
  0x01 => :method_argument_names,
  0x02 => :instance_method_argument_types,
  0x03 => :instance_method_argument_names,
}.freeze

REFLECTION_REV = REFLECTION.map { |k, v| [v, k] }.to_h
