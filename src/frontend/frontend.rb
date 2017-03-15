require_relative './shared.rb'

def read_test_file(fname)
  base = base_read_test_file(fname)

  code = base[:code]
  expected_status = nil
  body = base[:expect_ok]
  compile_error = base[:expect_compile_error].presence
  if compile_error
    expected_status = :compile_error
  end

  {
    code: code,
    expected_status: expected_status,
    expected_body: body,
    expected_compile_error: compile_error,
  }
end

def compile_to_asm(input, output)
  run_ruby_part(input, output, 'compile to DabASM', 'compiler')
end

def assemble(input, output)
  run_ruby_part(input, output, 'assemble DabASM', 'tobinary')
end

def execute(input, output)
  describe_action(input, output, 'VM') do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    cmd = "timeout 10 ./bin/cvm < #{input} > #{output}"
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

def extract_source(input, output)
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

  data = read_test_file(input)

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  dab = Pathname.new(test_output_dir).join(File.basename(input).ext('.dab')).to_s
  asm = Pathname.new(test_output_dir).join(File.basename(input).ext('.dabca')).to_s
  bin = Pathname.new(test_output_dir).join(File.basename(input).ext('.dabcb')).to_s
  out = Pathname.new(test_output_dir).join(File.basename(input).ext('.out')).to_s

  extract_source(input, dab)
  begin
    compile_to_asm(dab, asm)
  rescue SystemCommandError => e
    if data[:expected_status] == :compile_error
      compare_output('compare compiler output', e.stderr, data[:expected_compile_error], true)
      FileUtils.touch(out)
      return
    else
      raise e
    end
  end
  if data[:expected_status] == :compile_error
    raise "Expected compiler error in #{input}"
  end
  assemble(asm, bin)
  execute(bin, out)

  test_body = data[:expected_body]
  actual_body = open(out).read.strip
  begin
    compare_output(info, actual_body, test_body)
  rescue DabCompareError
    FileUtils.rm(out)
    raise
  end
end

if $settings[:input].downcase.end_with? '.dabt'
  run_test($settings)
end
