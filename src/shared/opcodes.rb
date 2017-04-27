OPCODES = {
  0x00 => {name: 'START_FUNCTION', args: %i(vlc uint16 uint16 uint16)}, # function name, class index (or -1), number of local variables, body length
  0x01 => {name: 'CONSTANT_SYMBOL', arg: :vlc}, # symbol
  0x02 => {name: 'CONSTANT_STRING', arg: :vlc}, # string
  0x03 => {name: 'PUSH_CONSTANT', arg: :uint16}, # constant index, push(1)
  0x04 => {name: 'CALL', args: %i(uint16 uint16)}, # n = number of arguments, n2 = number of retvals, pop(n + 1), push(n2)
  0x05 => {name: 'SET_VAR', arg: :uint16}, # local variable index, pop(1)
  0x06 => {name: 'PUSH_VAR', arg: :uint16}, # local variable index, push(1)
  0x07 => {name: 'PUSH_ARG', arg: :uint16}, # argument index, push(1)
  0x08 => {name: 'CONSTANT_NUMBER', arg: :uint64}, # number
  0x09 => {name: 'RETURN', arg: :uint16}, # pop(n)
  0x0A => {name: 'JMP', arg: :int16}, # add +arg to PC
  0x0B => {name: 'JMP_IFN', arg: :int16}, # pop(1), add +arg to PC if value from stack is false
  0x0C => {name: 'NOP'}, #
  0x0D => {name: 'PUSH_NIL'}, # push(1)
  0x0E => {name: 'KERNELCALL', arg: :uint8}, # depends on the call
  0x0F => {name: 'START_CLASS', args: %i(vlc uint16)}, # DEPRECATED
  0x10 => {name: 'PUSH_CLASS', arg: :uint16}, # push(1)
  0x11 => {name: 'INSTCALL', args: %i(uint16 uint16)}, # n = number of arguments, n2 = number of retvals, pop(n + 2), push(n2)
  0x12 => {name: 'PUSH_SELF'}, # push(1)
  0x13 => {name: 'PUSH_INSTVAR', arg: :vlc}, # push(1)
  0x14 => {name: 'SET_INSTVAR', arg: :vlc}, # pop(1)
  0x15 => {name: 'PUSH_ARRAY', arg: :uint16}, # pop(arg), push(1)
  0x16 => {name: 'PUSH_TRUE'}, # push(1)
  0x17 => {name: 'PUSH_FALSE'}, # push(1)
  0x18 => {name: 'BREAK_LOAD'}, # stop loading the code
  0x19 => {name: 'LOAD_FUNCTION', args: %i(uint16 vlc uint16)}, # [address, name, classIndex]
  0x1A => {name: 'DEFINE_CLASS', args: %i(vlc uint16 uint16)}, # n = name, n2 = class index, n3 = base class index
  0x1B => {name: 'STACK_RESERVE', args: [:uint16]}, # reserve space (for ie. local variables)
  0x1C => {name: 'COV_FILE', args: %i(uint16 vlc)}, # args: filehash, filename
  0x1D => {name: 'COV', args: %i(uint16 uint16)}, # args: filehash, fileline
  0x1E => {name: 'DUP'}, # push(1)
  0x1F => {name: 'JMP_IF', arg: :int16}, # pop(1), add +arg to PC if value from stack is true
  0x20 => {name: 'POP', arg: :uint16}, # pop(n)
}.freeze

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
