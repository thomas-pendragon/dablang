require_relative './shared'

def read_test_file(fname)
  base_read_test_file(fname)
end

def calculate_coverage(input, output)
  options = ''
  run_ruby_part(input, output, 'calculate coverage', 'cov', "--format=plaintext#{options}", true)
end

def extract_format_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:code]
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

  dab = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dab')).to_s
  cov = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.cov')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s

  extract_format_source(input, dab)
  calculate_coverage(dab, cov)

  test_body = data[:expect]
  actual_body = open(cov).read.strip
  begin
    compare_output(info, actual_body, test_body)
    File.open(out, 'wb') { |f| f << '1' }
  rescue DabCompareError
    FileUtils.rm(out)
    raise
  end
end

if $settings[:input].downcase.end_with? '.test'
  run_test($settings)
end
