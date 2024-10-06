require 'json'
data = JSON.parse(File.read('rpg1.json'))['layers'][0]['tiles']
map = Array.new(64) { Array.new(64) }
data.each do |item|
  x = item['x'].to_i / 16
  y = item['y'].to_i / 16
  map[x][y] = item['id'].to_i
end

str = []

def pack_custom(values)
  # Combine the values using bitwise operations
  combined = (values[0] << 6) | (values[1] << 2) | (values[2] << 1) | values[3]
  
  # Pack the combined bits into a binary string
  [combined].pack('S>') # S> is for 16-bit big-endian integer
end

64.times do |x|
  64.times do |y|
    v = map[x][y] || 0x1b
    STDERR.printf('%02x', v)
    str << pack_custom([v, 0, 0, 0])#.pack('B10B4B1B1')
  end
  STDERR.puts
end

puts str.join
