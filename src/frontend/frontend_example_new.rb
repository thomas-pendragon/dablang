require_relative './shared_noautorun'

$autorun = true if $autorun.nil?

class DabExampleSpec
  include BaseFrontend

  def execute(input, output, run_options)
    input = [input] unless input.is_a?(Array)
    describe_action(input, output, 'VM') do
      input = input.map(&:to_s).map(&:shellescape).join(' ')
      output = output.to_s.shellescape
      run_options = run_options.presence
      cmd = "./bin/cvm #{run_options} #{input} --out=#{output}"
      begin
        qsystem(cmd, timeout: 10)
      rescue SystemCommandError => e
        STDERR.puts
        warn e.stderr
        STDERR.puts
        e.stdout = open(output).read
        FileUtils.rm(output)
        raise
      end
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
end

if $autorun
  read_args!

  test = DabExampleSpec.new
  test.run_test($settings)
end
