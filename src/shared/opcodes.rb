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
  0x0A => {name: 'JMP', arg: :uint16}, # add +arg to PC
  0x0B => {name: 'JMP_IFN', arg: :uint16}, # pop(1), add +arg to PC if value from stack is false
  0x0C => {name: 'NOP'}, #
  0x0D => {name: 'CONSTANT_BOOLEAN', arg: :uint16}, # bool (true/false)
  0x0E => {name: 'PUSH_NIL'}, # push(1)
  0x0F => {name: 'KERNELCALL', arg: :uint8}, # depends on the call
  0x10 => {name: 'START_CLASS', args: %i(vlc uint16)},
  0x11 => {name: 'PUSH_CLASS', arg: :uint16}, # push(1)
  0x12 => {name: 'INSTCALL', args: %i(uint16 uint16)}, # n = number of arguments, n2 = number of retvals, pop(n + 2), push(n2)
  0x13 => {name: 'PUSH_SELF'}, # push(1)
  0x14 => {name: 'PUSH_INSTVAR', arg: :vlc}, # push(1)
  0x15 => {name: 'SET_INSTVAR', arg: :vlc}, # pop(1)
  0x16 => {name: 'PUSH_ARRAY', arg: :uint16}, # pop(arg), push(1)
}.freeze

OPCODES_REV = OPCODES.map { |k, v| [v[:name], v.merge(opcode: k)] }.to_h

KERNELCODES = {
  0x00 => 'PRINT',
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
