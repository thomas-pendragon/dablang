OPCODES = {
  0x00 => {name: 'START_FUNCTION', args: %i(vlc uint16 uint16)}, # function name, number of local variables, body length
  0x01 => {name: 'CONSTANT_SYMBOL', arg: :vlc}, # symbol
  0x02 => {name: 'CONSTANT_STRING', arg: :vlc}, # string
  0x03 => {name: 'PUSH_CONSTANT', arg: :uint16}, # constant index, push(1)
  0x04 => {name: 'CALL', arg: :uint16}, # n = number of arguments, pop(n + 1)
  0x05 => {name: 'SET_VAR', arg: :uint16}, # local variable index, pop(1)
  0x06 => {name: 'PUSH_VAR', arg: :uint16}, # local variable index, push(1)
  0x07 => {name: 'PUSH_ARG', arg: :uint16}, # argument index, push(1)
  0x08 => {name: 'CONSTANT_NUMBER', arg: :uint64}, # number
  0x09 => {name: 'RETURN'}, # pop(1)
  0x0A => {name: 'JMP', arg: :uint16}, # add +arg to PC
  0x0B => {name: 'JMP_IFN', arg: :uint16}, # pop(1), add +arg to PC if value from stack is false
  0x0C => {name: 'NOP'}, #
  0x0D => {name: 'CONSTANT_BOOLEAN', arg: :uint16}, # bool (true/false)
  0x0E => {name: 'PUSH_NIL'}, # push(1)
  0x0F => {name: 'KERNELCALL', arg: :uint8}, # depends on the call
}.freeze

OPCODES_REV = OPCODES.map { |k, v| [v[:name], v.merge(opcode: k)] }.to_h

KERNELCODES = {
  0x00 => 'PRINT',
}.freeze

KERNELCODES_REV = KERNELCODES.map { |k, v| [v, k] }.to_h
