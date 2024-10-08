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
      {name: 'NOP'},
    ],
  },
  {
    group: 'MOV',
    items:
    [
      {name: 'MOV', args: %i[reg reg]}, # reg0 <- reg1

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
      {name: 'LOAD_CLASS_EX', args: %i[reg uint16 reglist]}, # reg0 -> class(arg1)<arg2..argN>
      {name: 'LOAD_METHOD', args: %i[reg symbol]}, # reg0 <- method[sym1]
      {name: 'REFLECT', args: %i[reg symbol uint16 uint16]}, # reg0 <- reflect(sym1) with type arg2, klass=arg3

      {name: 'LOAD_NUMBER', args: %i[reg uint64]}, # reg0 <- arg1
      {name: 'LOAD_STRING', args: %i[reg uint64 uint64]}, # reg0 <- string(*arg1, length = arg2)
      {name: 'NEW_ARRAY', args: %i[reg reglist]}, # reg0 <- [reg(arg1), reg(arg2), ... reg(argn)]

      {name: 'LOAD_SELF', args: %i[reg]}, # reg0 <- self
      {name: 'GET_INSTVAR', args: %i[reg symbol]}, # reg0 <- self.@arg1
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

      {name: 'CALL', args: %i[reg symbol reglist]}, # reg0 <- call(symbol(arg1), arg2..argn)

      {name: 'INSTCALL', args: %i[reg reg symbol reglist]}, # reg0 <- call(symbol(arg2), self: arg1, args: arg3..argn)

      {name: 'SYSCALL', args: %i[reg uint8 reglist]}, # reg0 <- syscall(arg1, arg2...argn)

      {name: 'RETURN', args: %i[reg]}, # return(reg0)
    ],
  },
  {
    group: 'OTHER',
    items:
    [
      {name: 'RETAIN', args: %i{reg}}, # retain(reg0)
      {name: 'RELEASE', args: %i{reg}}, # release(reg0)
      {name: 'CAST', args: %i[reg reg uint16]}, # reg0 <- reg(arg1) as arg2
      {name: 'SET_INSTVAR', args: %i{symbol reg}}, # self.@arg0 <- reg(arg1)
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
    items: [
      {name: 'LOAD_FLOAT', args: %i{reg float}}, # reg0 <- arg1
      {name: 'LOAD_ARG_DEFAULT', args: %i[reg uint16 reg]}, # reg0 <- funarg(arg1) || arg2
      {name: 'LOAD_LOCAL_BLOCK', args: %i[reg reg]}, # reg0 <- local_block(reg1)
      {name: 'LOAD_CURRENT_BLOCK', args: %i[reg]}, # reg0 <- local_block or nil
      {name: 'BOX', args: %i[reg reg]}, # reg0 <- create new box(reg1)
      {name: 'UNBOX', args: %i[reg reg]}, # reg0 <- unbox(reg1)
      {name: 'SETBOX', args: %i[reg reg reg]}, # reg0 <- update box(reg1) with value(reg2)
      {name: 'GET_INSTVAR_EXT', args: %i[reg symbol reg]}, # reg0 <- @arg2.@arg1
      {name: 'GET_CLASSVAR', args: %i[reg symbol]}, # reg0 <- Self.@arg1
      {name: 'SET_CLASSVAR', args: %i{symbol reg}}, # Self.@arg0 <- reg(arg1)
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
      {name: 'W_CLASS', args: %i[uint16 uint16 symbol]}, # arg0 = class index arg1 = parent class index arg2 = name
      {name: 'W_METHOD', args: %i[symbol uint16 uint64 uint16 uint64 uint8]}, # arg0 = symbol arg1 = class index arg2 = address, arg3 = number of args (for reflection) arg4 = length arg5 = flags
      {name: 'W_METHOD_ARG', args: %i[symbol uint16]}, # arg0 = name arg1 = type
      {name: 'W_COV_FILE', args: %i[uint64]}, # arg0 = cstr pointer
      {name: 'W_BYTE', args: %i[uint8]}, # arg0 = byte
    ],
  },
].freeze

OPCODES_ARRAY = OPCODES_ARRAY_BASE.flat_map { |item| item[:items] }

OPCODES_PSEUDO_ARRAY = OPCODES_ARRAY_BASE.flat_map { |item| item[:items].map { |_| item[:pseudo] || false } }

REAL_OPCODES_ARRAY = OPCODES_ARRAY.select.with_index { |_item, index| !OPCODES_PSEUDO_ARRAY[index] }

OPCODES = ((0...OPCODES_ARRAY.size).zip OPCODES_ARRAY).to_h.freeze
REAL_OPCODES = ((0...REAL_OPCODES_ARRAY.size).zip REAL_OPCODES_ARRAY).to_h.freeze

OPCODES_REV = OPCODES.map { |k, v| [v[:name], v.merge(opcode: k)] }.to_h

METHOD_FLAGS = {
  static: 1 << 0,
}.freeze

KERNELCODES = {
  0x00 => 'PRINT',
  0x01 => 'EXIT',
  0x02 => 'USECOUNT', # 65535 if stack, 65536 if static
  0x03 => 'TO_SYM',
  0x04 => 'FETCH_INT32',
  0x05 => 'DEFINE_METHOD',
  0x06 => 'BYTESWAP32',
  0x07 => 'DLIMPORT',
  0x08 => 'WARN',
  0x09 => 'DEFINE_CLASS',
  0x0A => 'GET_INSTVAR',
  0x0B => 'SET_INSTVAR',
  0x0C => 'ANSI_COLOR',
}.freeze

KERNELCODES_REV = KERNELCODES.map { |k, v| [v, k] }.to_h

SYSCALLS = KERNELCODES.values.map { "__#{_1.downcase}" }

require_relative 'classes'

REFLECTION = {
  0x00 => :method_arguments,
  0x01 => :method_argument_names,
  0x02 => :instance_method_argument_types,
  0x03 => :instance_method_argument_names,
}.freeze

REFLECTION_REV = REFLECTION.map { |k, v| [v, k] }.to_h
