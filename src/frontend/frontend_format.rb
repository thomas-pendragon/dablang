require_relative './shared.rb'

def read_test_file(fname)
  base_read_test_file(fname)
end

def format_source(input, output)
  run_ruby_part(input, output, 'format source', 'format', $settings[:options])
end

def extract_format_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:input]
    File.open(output, 'wb') do |file|
      file << text
    end
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'
  test_prefix = settings[:test_output_prefix] || ''

  data = read_test_file(input)

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  din = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.in.dab')).to_s
  dout = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out.dab')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s

  extract_format_source(input, din)
  format_source(din, dout)

  test_body = data[:output]
  actual_body = open(dout).read.strip
  begin
    compare_output(info, actual_body, test_body)
    File.open(out, 'wb') { |f| f << '1' }
  rescue DabCompareError
    FileUtils.rm(out) if File.exist?(out)
    raise
  end
end

if $settings[:input].downcase.end_with? '.dabft'
  run_test($settings)
end
