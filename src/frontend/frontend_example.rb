require_relative 'shared'

def compile_to_asm(input, output, options)
  run_ruby_part(input, output, 'compile to DabASM', 'compiler', options, true)
end

def assemble(input, output)
  run_ruby_part(input, output, 'assemble DabASM', 'tobinary')
end

def execute(input, run_options)
  describe_action(input, '-', 'VM') do
    input = input.to_s.shellescape
    cmd = "./bin/cvm #{run_options}"

    qsystem(cmd, input_file: input)
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = './tmp/'
  test_prefix = settings[:test_output_prefix] || 'example_'

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  dab = input
  asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dabca')).to_s
  bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dabcb')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s

  stdlib_path = File.expand_path("#{File.dirname(__FILE__)}/../../stdlib/")
  stdlib_glob = "#{stdlib_path}/*.dab"
  stdlib_files = Dir.glob(stdlib_glob)

  options = ''
  run_options = options

  compile_to_asm(([dab] + stdlib_files).compact, asm, options)

  assemble(asm, bin)

  if $dont_run_example
    File.open(out, 'wb') { |f| f << '1' }
  else
    execute(bin, run_options)
  end
end

run_test($settings)
