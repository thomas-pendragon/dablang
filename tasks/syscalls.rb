require_relative '../src/shared/opcodes.rb'

puts '// Autogenerated from /src/shared/opcodes.rb'
puts
puts 'enum'
puts '{'

max_name_len = KERNELCODES.map { |_k, v| v.length }.max
max_value_len = KERNELCODES.map { |k, _v| sprintf('%x', k).length }.max

format = "    KERNEL_%-#{max_name_len}s = 0x%0#{max_value_len}X,\n"

KERNELCODES.each do |key, name|
  printf(format, name, key)
end

puts '};'
