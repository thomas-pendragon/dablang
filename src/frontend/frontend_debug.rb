require_relative './shared.rb'

def read_test_file(fname)
  base_read_test_file(fname)
end

def compile_to_asm(input, output)
  run_ruby_part(input, output, 'compile to DabASM', 'compiler', nil, true)
end

def assemble(input, output)
  run_ruby_part(input, output, 'assemble DabASM', 'tobinary')
end

def execute(input, extra_input, output, error_output)
  describe_action(input, output, 'VM') do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    cmd = "timeout 10 ./bin/cvm --debug #{input} < #{extra_input} > #{output} 2> #{error_output}"
    begin
      psystem_noecho cmd
    rescue SystemCommandError => e
      STDERR.puts
      STDERR.puts e.stderr
      STDERR.puts
      FileUtils.rm(output)
      raise
    end
  end
end

def extract_source(input, output, text)
  describe_action(input, output, 'extract source') do
    File.open(output, 'wb') do |file|
      file << text << "\n"
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

  inp = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.in')).to_s
  dab = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dab')).to_s
  asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dabca')).to_s
  bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dabcb')).to_s
  vmo = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.vm')).to_s
  vme = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.vme')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s

  FileUtils.rm(out) if File.exist?(out)

  extract_source(input, dab, data[:code])
  extract_source(input, inp, data[:input])

  stdlib_path = File.expand_path(File.dirname(__FILE__) + '/../../stdlib/')
  stdlib_glob = stdlib_path + '/*.dab'
  stdlib_files = Dir.glob(stdlib_glob)
  begin
    extra = data[:included_file]
    if extra
      extra = "./test/shared/#{extra}.dab"
    end
    compile_to_asm(([dab, extra] + stdlib_files).compact, asm)
  rescue SystemCommandError => e
    if data[:expected_status] == :compile_error
      compare_output('compare compiler output', e.stderr, data[:expected_compile_error], true)
      File.open(out, 'wb') { |f| f << '1' }
      return
    else
      raise e
    end
  end
  if data[:expected_status] == :compile_error
    raise "Expected compiler error in #{input}"
  end
  assemble(asm, bin)

  begin
    execute(bin, inp, vmo, vme)
  rescue SystemCommandError => e
    if data[:expected_status] == :runtime_error
      compare_output('compare runtime output', e.stderr, data[:expected_runtime_error], true)
      File.open(out, 'wb') { |f| f << '1' }
      return
    else
      raise e
    end
  end

  test_body = data[:expect_stdout]
  actual_body = open(vmo).read.strip
  begin
    compare_output(info, actual_body, test_body)
  rescue DabCompareError
    raise
  end

  # test_body = data[:expect_stderr]
  # actual_body = open(vme).read.strip
  # begin
  #   compare_output(info, actual_body, test_body)
  #   File.open(out, 'wb') { |f| f << '1' }
  # rescue DabCompareError
  #   raise
  # end
end

if $settings[:input].downcase.end_with? '.test'
  run_test($settings)
end
