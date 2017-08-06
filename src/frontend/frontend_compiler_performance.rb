require_relative './shared.rb'

def read_test_file(fname)
  base_read_test_file(fname)
end

def extract_format_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:input]
    File.open(output, 'wb') do |file|
      file << text
    end
  end
end

def compile(input, output, options)
  run_ruby_part(input, output, 'compile', 'compiler', options, true)
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'
  test_prefix = settings[:test_output_prefix] || ''

  data = read_test_file(input)

  options = data[:options] || ''

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  dab = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dab')).to_s
  asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.asm')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s
  FileUtils.rm(out) if File.exist?(out)

  extract_format_source(input, dab)

  start = Time.now
  options += ' --show-benchmark'
  compile(dab, asm, options)
  finish = Time.now

  clock_time = finish - start
  output = File.read(asm)
  unless output =~ /Total running time: (\d+\.\d+)s/
    raise DabCompareError.new('no benchmark result')
  end
  benchmark_time = $1.to_f
  printf("Clock time: %.2fs\n", clock_time)
  printf("Bench time: %.2fs\n", benchmark_time)

  acceptable_time = data[:acceptable_time].to_f

  if benchmark_time > acceptable_time
    puts "#{info}... ERROR!".red.bold
    puts "Acceptable time was: #{acceptable_time}s".red
    puts "Actual time was:     #{benchmark_time}s".red
    raise DabCompareError.new('test error')
  end

  File.open(out, 'wb') { |f| f << '1' }
end

if $settings[:input].downcase.end_with? '.test'
  run_test($settings)
end
