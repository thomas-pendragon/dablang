require_relative 'shared_noautorun'
require_relative '../compiler/_requires'

$autorun = true if $autorun.nil?

class FormatSpec
  include BaseFrontend

  def read_test_file(fname)
    base_read_test_file(fname)
  end

  def format_source(input, output, settings)
    input_data = File.read(input)
    stream = DabProgramStream.new(input_data)
    compiler = DabCompiler.new(stream)
    program = compiler.program
    options = settings[:options]
    File.open(output, 'wb') { |f| f << program.formatted_source(options) }
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
    format_source(din, dout, {})

    test_body = data[:output]
    actual_body = open(dout).read.strip
    begin
      compare_output(info, actual_body, test_body)
      File.open(out, 'wb') { |f| f << '1' }
    rescue DabCompareError
      FileUtils.rm_f(out)
      raise
    end
  end
end

if $autorun
  read_args!
  raise 'no dabft' unless $settings[:input].downcase.end_with?('.dabft')

  test = FormatSpec.new
  test.run_test($settings)
end
