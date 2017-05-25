require_relative '../setup.rb'

directories = Dir['./test/*']

directories.each do |directory|
  next if directory.end_with?('/shared')
  list = Dir[directory + '/*']
  list = list.map { |item| File.basename(item) }.sort
  list.each_with_index do |item, index|
    start = sprintf('%04d_', index + 1)
    next if item.start_with?(start)
    list.each_with_index do |preview_item, preview_index|
      next unless ((index - 2)..(index + 2)).cover?(preview_index)
      STDERR.printf("  %s %s\n", preview_index == index ? '>' : ' ', preview_item)
    end
    STDERR.puts "#{directory}/#{item} is incorrect! (expected to start with #{start})."
    exit 1
  end
end
