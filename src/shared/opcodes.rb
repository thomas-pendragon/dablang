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
    group: 'MOV',
    items:
    [
      {name: 'MOV', args: %i[reg reg]}, # reg0 <- reg(arg1)

      {name: 'LOAD_NIL', args: %i[reg]}, # reg0 <- nil
      {name: 'LOAD_TRUE', args: %i[reg]}, # reg0 <- true
      {name: 'LOAD_FALSE', args: %i[reg]}, # reg0 <- false

      {name: 'LOAD_UINT8', args: %i{reg uint8}}, # reg0 <- arg1
      {name: 'LOAD_UINT16', args: %i{reg uint16}}, # reg0 <- arg1
      {name: 'LOAD_UINT32', args: %i{reg uint32}}, # reg0 <- arg1
      {name: 'LOAD_UINT64', args: %i{reg uint64}}, # reg0 <- arg1
      {name: 'LOAD_INT8', args: %i{reg int8}}, # reg0 <- arg1
      {name: 'LOAD_INT16', args: %i{reg int16}}, # reg0 <- arg1
      {name: 'LOAD_INT32', args: %i{reg int32}}, # reg0 <- arg1
      {name: 'LOAD_INT64', args: %i{reg int64}}, # reg0 <- arg1

      {name: 'LOAD_CLASS', args: %i[reg uint16]}, # reg0 <- class(arg1)
      {name: 'LOAD_METHOD', args: %i[reg symbol]}, # reg0 <- method[sym1]
      {name: 'REFLECT', args: %i[reg symbol uint16 uint16]}, # reg0 <- reflect(sym1) with type arg2, klass=arg3

      {name: 'LOAD_NUMBER', args: %i[reg uint64]}, # reg0 <- arg1
      {name: 'LOAD_STRING', args: %i[reg uint64 uint64]}, # reg0 <- string(*arg1, length = arg2)
      {name: 'NEW_ARRAY', args: %i[reg reglist]}, # reg0 <- [reg(arg1), reg(arg2), ... reg(argn)]

      {name: 'LOAD_SELF', args: %i[reg]}, # reg0 <- self
      {name: 'GET_INSTVAR', args: %i[reg symbol]}, # reg0 <- self.@arg1
      {name: 'LOAD_CLOSURE', args: %i[reg uint16]}, # reg0 <- closurevar(arg1)
      {name: 'LOAD_HAS_BLOCK', args: %i[reg]}, # reg0 <- has_block?

      {name: 'LOAD_ARG', args: %i[reg uint16]}, # reg0 <- funarg(arg1)
    ],
  },
  {
    group: 'FLOW',
    items:
    [
      {name: 'JMP', args: %i{int16}}, # add +arg to PC
      {name: 'JMP_IF', args: %i[reg int16 int16]}, # add +arg1/2 to PC depending on reg0

      {name: 'Q_SET_CALL', args: %i[reg symbol reglist]}, # reg0 <- call(symbol(arg1), arg2..argn)
      {name: 'Q_SET_CALL_BLOCK', args: %i[reg symbol symbol reg reglist]}, # reg0 <- call(symbol(arg1), block=arg2, capture=arg3, arg4..argn)

      {name: 'Q_SET_INSTCALL', args: %i[reg reg symbol reglist]}, # reg0 <- call(symbol(arg2), self: arg1, args: arg3..argn)
      {name: 'Q_SET_INSTCALL_BLOCK', args: %i[reg reg symbol symbol reg reglist]}, # reg0 <- call(symbol(arg2), self: arg1, block: arg3, capture: arg4, args: arg5..argn)

      {name: 'Q_SET_SYSCALL', args: %i[reg uint8 reglist]}, # reg0 <- syscall(arg1, arg2...argn)

      {name: 'Q_YIELD', args: %i[reg reglist]}, # yield(reg0..reg(argn))

      {name: 'Q_RETURN', args: %i[reg]}, # return(reg0)
    ],
  },
  {
    group: 'OTHER',
    items:
    [
      {name: 'Q_RETAIN', args: %i{reg}}, # retain(reg0)
      {name: 'Q_RELEASE', args: %i{reg}}, # release(reg0)
      {name: 'Q_CAST', args: %i[reg reg uint16]}, # reg0 <- reg(arg1) as arg2
      {name: 'Q_CHANGE_INSTVAR', args: %i{symbol reg}}, # self.@arg0 <- reg(arg1)
    ],
  },
  {
    group: 'SPECIAL',
    items:
    [
      {name: 'COV', args: %i(uint16 uint16)}, # args: filehash, fileline
      {name: 'STACK_RESERVE', args: [:uint16]}, # reserve space (for ie. local variables)
    ],
  },
  {
    group: 'NEW',
    items:
    [
    ],
  },
  {
    group: 'PSEUDO HEADER OPCODES',
    pseudo: true,
    items:
    [
      {name: 'W_HEADER', args: %i[uint16]}, # dump header, version number = arg0
      {name: 'W_SECTION', args: %i[uint16 string4]}, # header entry, address = arg0, label = arg1
      {name: 'W_END_HEADER'}, # finish header
      {name: 'W_STRING', args: %i[cstring]}, # raw data, zero byte limited
      {name: 'W_SYMBOL', args: %i[uint64]}, # define symbol at address, zero-terminated
      {name: 'W_METHOD', args: %i[symbol uint16 uint64]}, # arg0 = symbol arg1 = class index arg2 = address
      {name: 'W_CLASS', args: %i[uint16 uint16 symbol]}, # arg0 = class index arg1 = parent class index arg2 = name
      {name: 'W_METHOD_EX', args: %i[symbol uint16 uint64 uint16]}, # arg0 = symbol arg1 = class index arg2 = address, arg3 = number of args (for reflection)
      {name: 'W_METHOD_ARG', args: %i[symbol uint16]}, # arg0 = name arg1 = type
      {name: 'W_COV_FILE', args: %i[uint64]}, # arg0 = cstr pointer
    ],
  },
].freeze

OPCODES_ARRAY = OPCODES_ARRAY_BASE.flat_map { |item| item[:items] }

OPCODES_PSEUDO_ARRAY = OPCODES_ARRAY_BASE.flat_map { |item| item[:items].map { |_| item[:pseudo] || false } }

REAL_OPCODES_ARRAY = OPCODES_ARRAY.select.with_index { |_item, index| !OPCODES_PSEUDO_ARRAY[index] }

OPCODES = Hash[(0...OPCODES_ARRAY.size).zip OPCODES_ARRAY].freeze
REAL_OPCODES = Hash[(0...REAL_OPCODES_ARRAY.size).zip REAL_OPCODES_ARRAY].freeze

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
