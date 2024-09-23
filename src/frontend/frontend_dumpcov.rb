require_relative 'shared'

def read_test_file(fname)
  base_read_test_file(fname)
end

def extract_format_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:code]
    File.open(output, 'wb') do |file|
      file << text
      file << "\n"
    end
  end
end

def dumpcov(input, output, options)
  describe_action(input, output, 'dumpcov') do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    cmd = "./bin/cdumpcov #{options}"
    qsystem(cmd, input_file: input, output_file: output, timeout: 10)
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'
  test_prefix = settings[:test_output_prefix] || ''

  data = read_test_file(input)

  newformat_option = ''

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.asm')).to_s
  bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.bin')).to_s
  cov = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.cov')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s
  FileUtils.rm_f(out)

  extract_format_source(input, asm)
  assemble(asm, bin, newformat_option)
  dumpcov(bin, cov, newformat_option)

  expected = data[:expect].strip

  actual = File.read(cov).strip
  compare_output(info, actual, expected)

  File.open(out, 'wb') { |f| f << '1' }
end

if $settings[:input].downcase.end_with? '.test'
  run_test($settings)
end
