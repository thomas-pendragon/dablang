require_relative './shared_noautorun.rb'
require_relative '../compiler/compiler_noautorun.rb'
require_relative '../tobinary/tobinary.rb'

$autorun = true if $autorun.nil?

class DabSpec
  include BaseFrontend

  def read_test_file(fname)
    base = base_read_test_file(fname)

    code = base[:code]
    expected_status = nil
    body = base[:expect_ok]
    run = base[:run]
    compile_error = base[:expect_compile_error].presence
    runtime_error = base[:expect_runtime_error].presence
    if compile_error
      expected_status = :compile_error
    end
    if runtime_error
      expected_status = :runtime_error
    end
    if run == 'minitest0'
      included_file = 'minitest0'
      body = 'all test ok'
    end

    {
      code: code,
      expected_status: expected_status,
      expected_body: body,
      expected_compile_error: compile_error,
      expected_runtime_error: runtime_error,
      included_file: included_file,
      options: base[:options],
      run_options: base[:run_options],
    }
  end

  def execute(input, output, run_options)
    describe_action(input, output, 'VM') do
      input = input.to_s.shellescape
      output = output.to_s.shellescape
      run_options = run_options.presence&.shellescape
      cmd = "timeout 10 ./bin/cvm #{run_options} #{input} --out=#{output}"
      begin
        psystem_noecho cmd
      rescue SystemCommandError => e
        STDERR.puts
        STDERR.puts e.stderr
        STDERR.puts
        e.stdout = open(output).read
        FileUtils.rm(output)
        raise
      end
    end
  end

  def extract_source(input, output, text)
    describe_action(input, output, 'extract source') do
      File.open(output, 'wb') do |file|
        file << text
      end
    end
  end

  def run(_settings)
    data = read_test_file(input)

    info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
    puts info
    FileUtils.mkdir_p(test_output_dir)

    dab = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dab')).to_s
    asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dabca')).to_s
    bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dabcb')).to_s
    vmo = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.vm')).to_s
    out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s

    FileUtils.rm(out) if File.exist?(out)

    extract_source(input, dab, data[:code])

    stdlib_path = File.expand_path(File.dirname(__FILE__) + '/../../stdlib/')
    stdlib_glob = stdlib_path + '/*.dab'
    stdlib_files = Dir.glob(stdlib_glob)
    begin
      extra = data[:included_file]
      if extra
        extra = "./test/shared/#{extra}.dab"
      end
      compile_dab_to_asm(([dab, extra] + stdlib_files).compact, asm, data[:options])
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
      execute(bin, vmo, data[:run_options])
    rescue SystemCommandError => e
      if data[:expected_status] == :runtime_error
        compare_output('compare runtime output', e.stdout, data[:expected_runtime_error], true)
        File.open(out, 'wb') { |f| f << '1' }
        return
      else
        raise e
      end
    end

    if data[:expected_status] == :runtime_error
      puts "#{info}: expected to fail, but succeeded instead".red.bold
      raise DabCompareError.new
    end

    test_body = data[:expected_body]
    actual_body = open(vmo).read.strip
    begin
      compare_output(info, actual_body, test_body)
      File.open(out, 'wb') { |f| f << '1' }
    rescue DabCompareError
      raise
    end
  end
end

if $autorun
  read_args!
  raise 'no dabt' unless $settings[:input].downcase.end_with?('.dabt')
  test = DabSpec.new
  test.run_test($settings)
end
