require_relative 'shared_noautorun'
require_relative '../compiler/compiler_noautorun'

$autorun = true if $autorun.nil?

class AsmSpec
  include BaseFrontend

  def read_test_file(fname)
    base_read_test_file(fname)
  end

  def extract_format_source(input, output)
    describe_action(input, output, 'extract source') do
      text = read_test_file(input)[:code]
      File.open(output, 'wb') do |file|
        file << text
      end
    end
  end

  def compile(input, output, options)
    compile_dab_to_asm(input, output, options)
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
    FileUtils.rm_f(out)

    extract_format_source(input, dab)
    begin
      compile(dab, asm, options)
    rescue SystemCommandError => e
      if data[:expect_compile_error].present?
        compare_output('compare compiler output', e.stderr, data[:expect_compile_error], true)
        File.open(out, 'wb') { |f| f << '1' }
        return
      else
        raise e
      end
    end

    raise 'expected compile error' if data[:expect_compile_error].present?

    expected = data[:expect].strip

    actual = File.read(asm).strip
    begin
      compare_output(info, actual, expected)
    rescue DabCompareError
      raise unless $autofix

      new_data = data.dup
      new_data[:expect] = actual.strip
      write_new_testspec(input, new_data)
    end

    File.open(out, 'wb') { |f| f << '1' }
  end
end

if $autorun
  read_args!
  raise 'no asmt' unless $settings[:input].downcase.end_with?('.asmt')

  test = AsmSpec.new
  test.run_test($settings)
end
