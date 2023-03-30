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
    test_output_dir = "./tmp/example_#{input}/"
    test_prefix = settings[:test_output_prefix] || 'example_'

    test_dir = Dir.glob(sprintf('./examples/%04d_*', input))[0]

    info = "Running test ##{input} #{test_dir.blue.bold} in directory #{test_output_dir.blue.bold}..."
    puts info
    FileUtils.mkdir_p(test_output_dir)

    levels = Dir.glob("#{test_dir}/level*").sort
    levels.each_with_index do |level_dir, level|
      info = "Running test ##{input} #{test_dir.blue.bold} level #{level.to_s.bold.blue} (#{level_dir.yellow})"
      puts info

      level_base = test_prefix + input.to_s + '_level' + level.to_s

      dab = Dir.glob(level_dir + '/*.dab')
      asm = Pathname.new(test_output_dir).join(level_base.ext('.dabca')).to_s
      bin = Pathname.new(test_output_dir).join(level_base.ext('.dabcb')).to_s
      out = Pathname.new(test_output_dir).join(level_base.ext('.out')).to_s

      stdlib_path = File.expand_path("#{File.dirname(__FILE__)}/../../stdlib/")
      stdlib_glob = "#{stdlib_path}/*.dab"
      stdlib_files = Dir.glob(stdlib_glob)

      options = ''
      run_options = options

      compile_dab_to_asm((dab + stdlib_files).compact, asm, options)
      raise 'a'
      assemble(asm, bin)

      if $dont_run_example
        File.open(out, 'wb') { |f| f << '1' }
      else
        execute(bin, run_options)
      end
    end
  end
end

if $autorun
  read_args!

  test = DabExampleSpec.new
  test.run_test($settings)
end
