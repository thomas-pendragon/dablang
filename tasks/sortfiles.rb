require_relative '../setup.rb'

autofix = ENV['AUTOFIX']&.to_i == 1

directories = Dir['./test/*']

directories.each do |directory|
  next if directory.end_with?('/shared')
  list = Dir[directory + '/*']
  list = list.map { |item| File.basename(item) }.sort
  list.each_with_index do |item, index|
    start = sprintf('%04d_', index + 1)
    next if item.start_with?(start)
    if autofix
      new_item = item.gsub(/^\d+_/, start)
      old_path = File.join(directory, item)
      new_path = File.join(directory, new_item)
      STDERR.puts "Correct: #{old_path} -> #{new_path}".red
      File.rename(old_path, new_path)
      next
    end
    list.each_with_index do |preview_item, preview_index|
      next unless ((index - 2)..(index + 2)).cover?(preview_index)
      STDERR.printf("  %s %s\n", preview_index == index ? '>' : ' ', preview_item)
    end
    STDERR.puts "#{directory}/#{item} is incorrect! (expected to start with #{start})."
    exit 1
  end
end
