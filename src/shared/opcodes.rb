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

OPCODES_ARRAY = [
  # NOP
  {name: 'NOP'}, #
  # PUSH
  {name: 'PUSH_NIL'}, # push(1)
  {name: 'PUSH_SELF'}, # push(1)
  {name: 'PUSH_TRUE'}, # push(1)
  {name: 'PUSH_FALSE'}, # push(1)
  {name: 'PUSH_STRING', arg: :vlc}, # push(1)
  {name: 'PUSH_NUMBER', arg: :uint64}, # push(1)
  {name: 'PUSH_ARRAY', arg: :uint16}, # pop(arg), push(1)
  {name: 'PUSH_CLASS', arg: :uint16}, # push(1)
  {name: 'PUSH_CONSTANT', arg: :uint16}, # constant index, push(1)
  {name: 'PUSH_ARG', arg: :uint16}, # argument index, push(1)
  {name: 'PUSH_VAR', arg: :uint16}, # local variable index, push(1)
  {name: 'PUSH_INSTVAR', arg: :vlc}, # push(1)
  # STACK
  {name: 'POP', arg: :uint16}, # pop(n)
  {name: 'DUP'}, # push(1)
  # CONSTANTS
  {name: 'CONSTANT_SYMBOL', arg: :vlc}, # symbol
  {name: 'CONSTANT_STRING', arg: :vlc}, # string
  {name: 'CONSTANT_NUMBER', arg: :uint64}, # number
  # CALL
  {name: 'CALL', args: %i(uint16 uint16)}, # n = number of arguments, n2 = number of retvals, pop(n + 1), push(n2)
  {name: 'INSTCALL', args: %i(uint16 uint16)}, # n = number of arguments, n2 = number of retvals, pop(n + 2), push(n2)
  {name: 'HARDCALL', args: %i(uint16 uint16)}, # n = number of arguments, n2 = number of retvals, pop(n + 1), push(n2)
  {name: 'SYSCALL', arg: :uint8}, # depends on the call
  # FLOW
  {name: 'JMP', arg: :int16}, # add +arg to PC
  {name: 'JMP_IF', arg: :int16}, # pop(1), add +arg to PC if value from stack is true
  {name: 'JMP_IFN', arg: :int16}, # pop(1), add +arg to PC if value from stack is false
  {name: 'RETURN', arg: :uint16}, # pop(n)
  # VARIABLES
  {name: 'SET_VAR', arg: :uint16}, # local variable index, pop(1)
  {name: 'SET_INSTVAR', arg: :vlc}, # pop(1)
  # COVERAGE
  {name: 'COV_FILE', args: %i(uint16 vlc)}, # args: filehash, filename
  {name: 'COV', args: %i(uint16 uint16)}, # args: filehash, fileline
  # OTHER
  {name: 'START_FUNCTION', args: %i(vlc uint16 uint16 uint16)}, # function name, class index (or -1), number of local variables, body length
  {name: 'LOAD_FUNCTION', args: %i(uint16 vlc uint16)}, # [address, name, classIndex]
  {name: 'STACK_RESERVE', args: [:uint16]}, # reserve space (for ie. local variables)
  {name: 'DEFINE_CLASS', args: %i(vlc uint16 uint16)}, # n = name, n2 = class index, n3 = base class index
  {name: 'BREAK_LOAD'}, # stop loading the code
].freeze

OPCODES = Hash[(0...OPCODES_ARRAY.size).zip OPCODES_ARRAY].freeze

OPCODES_REV = OPCODES.map { |k, v| [v[:name], v.merge(opcode: k)] }.to_h

KERNELCODES = {
  0x00 => 'PRINT',
  0x01 => 'EXIT',
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
).freeze

STANDARD_CLASSES_REV = STANDARD_CLASSES.each_with_index.map { |item, index| [item, index] }.to_h

USER_CLASSES_OFFSET = 0x100
