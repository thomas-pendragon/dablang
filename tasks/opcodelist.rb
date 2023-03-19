require_relative '../src/shared/opcodes'

puts '// Autogenerated from /src/shared/opcodes.rb'
puts
puts 'enum'
puts '{'

max_name_len = REAL_OPCODES.map { |_k, v| v[:name].length }.max
max_value_len = REAL_OPCODES.map { |k, _v| sprintf('%x', k).length }.max

format = "    OP_%-#{max_name_len}s = 0x%0#{max_value_len}X,\n"

REAL_OPCODES.each do |key, opcode|
  name = opcode[:name]
  printf(format, name, key)
end

puts '};'
