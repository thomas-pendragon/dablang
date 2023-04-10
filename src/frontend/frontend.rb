require_relative './shared_noautorun'

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
      options: base[:options] || '',
      run_options: base[:run_options] || '',
      frontend_options: base[:frontend_options] || '',
      skip: base[:skip]&.strip || '',
    }
  end

  def execute(input, output, run_options)
    input = [input].flatten
    describe_action(input, output, 'VM') do
      input = input.map { _1.to_s.shellescape }.join(' ')
      output = output.to_s.shellescape
      run_options = run_options.presence
      cmd = "./bin/cvm #{run_options} #{input} --out=#{output}"
      begin
        qsystem(cmd, timeout: 10)
      rescue SystemCommandError => e
        STDERR.puts
        warn e.stderr
        STDERR.puts
        e.stdout = File.read(output)
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

  def run(settings)
    data = read_test_file(input)

    stdlib_file = settings[:stdlib]

    if data[:skip] == 'windows' && OS.windows?
      puts "Skipping test  #{input.blue.bold} because Windows"
      return
    end

    info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
    puts info
    FileUtils.mkdir_p(test_output_dir)

    dab = temp_file('dab')
    asm = temp_file('dabca')
    bin = temp_file('dabcb')
    vmo = temp_file('vm')
    out = temp_file('out')

    FileUtils.rm_f(out)

    extract_source(input, dab, data[:code])

    # stdlib_path = File.expand_path("#{File.dirname(__FILE__)}/../../stdlib/")
    # stdlib_glob = "#{stdlib_path}/*.dab"
    # stdlib_files = Dir.glob(stdlib_glob)
    # stdlib_files = []

    no_stdlib = data[:frontend_options]['--no-stdlib']

    compile_options = data[:options]

    unless no_stdlib
      compile_options += " --ring-base[]=#{stdlib_file}"
    end

    assemble_options = ''

    run_options = data[:run_options]

    begin
      extra = data[:included_file]
      if extra
        extra = "./test/shared/#{extra}.dab"
      end
      compile_dab_to_asm([dab, extra].compact, asm, compile_options)
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

    assemble(asm, bin, assemble_options)

    bin_files = [bin]
    bin_files = [stdlib_file] + bin_files unless no_stdlib

    begin
      execute(bin_files, vmo, run_options)
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
