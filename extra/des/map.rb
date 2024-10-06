require 'json'
data = JSON.parse(File.read('rpg1_dump.json'))['layers'][0]['tiles']
map = Array.new(64) { Array.new(64) }
data.each do |item|
  x = item['x'].to_i# / 16
  y = item['y'].to_i# / 16
  map[x][y] = item['id'].to_i
end

str = []

def pack_custom(values)
  # Combine the values using bitwise operations
  combined = (values[0] << 6) | (values[1] << 2) | (values[2] << 1) | values[3]

  # Pack the combined bits into a binary string
  [combined].pack('S>') # S> is for 16-bit big-endian integer
end

def convert(in16, size:)
  x16 = in16 % size
  y16 = in16 / size
  #puts "#{in16} -> #{x16} / #{y16}"

  x8 = x16 * 2
  y8 = y16 * 2

  cc = ->(x,y){(x8+x)+(y8+y)*8}

  [cc[0,0],cc[1,0],cc[0,1],cc[1,1]]

  #abort
end

bigmap = Array.new(64) { Array.new(64) }

32.times do |x|
  32.times do |y|
    v = (map[x][y] || '28').to_i#0x1b
    STDERR.printf('%02x', v)
    2.times do |xx|
      2.times do |yy|
        indices = convert(v, size: 8)
        bigmap[x*2+0][y*2+0] = indices[0]
        bigmap[x*2+1][y*2+0] = indices[1]
        bigmap[x*2+0][y*2+1] = indices[2]
        bigmap[x*2+1][y*2+1] = indices[3]
      end
    end
  end
  STDERR.puts
end

64.times do |y|
  64.times do |x|
    v = bigmap[x][y]
    str << pack_custom([v, 0, 0, 0])
  end
end
puts str.join
