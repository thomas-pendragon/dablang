require_relative './shared_noautorun'
require_relative '../compiler/compiler_noautorun'

$autorun = true if $autorun.nil?

class DebugSpec
  include BaseFrontend

  def read_test_file(fname)
    base_read_test_file(fname)
  end

  def execute(input, extra_input, output, error_output)
    describe_action(input, output, 'VM') do
      input = input.to_s.shellescape
      output = output.to_s.shellescape
      begin
        qsystem("./bin/cvm --debug #{input}", timeout: 10, input_file: extra_input, output_file: output, error_file: error_output)
      rescue SystemCommandError
        FileUtils.rm(output) if File.exist?(output)
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

    options = data[:options] || ''
    frontend_options = data[:frontend_options] || ''

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

    extract_source(input, inp, data[:input])
    if data[:code].present?
      extract_source(input, dab, data[:code])

      stdlib_path = File.expand_path("#{File.dirname(__FILE__)}/../../stdlib/")
      stdlib_glob = "#{stdlib_path}/*.dab"
      stdlib_files = Dir.glob(stdlib_glob)

      stdlib_files = [] unless frontend_options['--with-stdlib']

      compile_dab_to_asm(([dab] + stdlib_files).compact, asm, options)
    elsif data[:asm_code].present?
      extract_source(input, asm, data[:asm_code])
    else
      raise 'no code'
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
      File.open(out, 'wb') { |f| f << '1' }
    rescue DabCompareError
      raise
    end
  end
end

if $autorun
  read_args!
  raise 'no test' unless $settings[:input].downcase.end_with?('.test')

  test = DebugSpec.new
  test.run_test($settings)
end
