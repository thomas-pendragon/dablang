OPCODES = {
  0x00 => {name: 'START_FUNCTION', arg: :vlc},
  0x01 => {name: 'CONSTANT_SYMBOL', arg: :vlc},
  0x02 => {name: 'CONSTANT_STRING', arg: :vlc},
  0x03 => {name: 'PUSH_CONSTANT', arg: :uint16},
  0x04 => {name: 'CALL', arg: :uint16},
  0x05 => {name: 'END_FUNCTION'},
  0x06 => {name: 'DEFINE_VAR'},
  0x07 => {name: 'VAR'},
}.freeze

OPCODES_REV = OPCODES.map { |k, v| [v[:name], v.merge(opcode: k)] }.to_h
