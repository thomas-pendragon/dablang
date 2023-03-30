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

    vmfiles = []

    levels = Dir.glob("#{test_dir}/level*").sort
    levels.each_with_index do |level_dir, level|
      is_final = level == (levels.count - 1)

      info = "Running test ##{input} #{test_dir.blue.bold} level #{level.to_s.bold.blue} (#{level_dir.yellow})"
      puts info

      level_base = "#{test_prefix}#{input}_level#{level}"

      dab = Dir.glob("#{level_dir}/*.dab")
      basepath = Pathname.new(test_output_dir)
      asm = basepath.join(level_base.ext('.dabca')).to_s
      bin = basepath.join(level_base.ext('.dabcb')).to_s
      out = basepath.join(level_base.ext('.out')).to_s
      vmo = basepath.join(level_base.ext('.vm')).to_s
      vmoa = basepath.join(level_base.ext('.vm.dabca')).to_s

      stdlib_path = File.expand_path("#{File.dirname(__FILE__)}/../../stdlib/")
      stdlib_glob = "#{stdlib_path}/*.dab"
      stdlib_files = (level == 0) ? Dir.glob(stdlib_glob) : []

      options = vmfiles.map{"--ring-base[]=#{_1}"}.join(' ')
      run_options = "--entry=level#{level}"
      run_options += ' --output=dumpvm' unless is_final
      run_options += ' --verbose'

      compile_dab_to_asm((dab + stdlib_files).compact, asm, options)
      assemble(asm, bin)
      execute(vmfiles + [bin], vmo, run_options)
      disassemble(vmo, vmoa, '--with-headers')

      vmfiles << vmo
    end
  end
end

if $autorun
  read_args!

  test = DabExampleSpec.new
  test.run_test($settings)
end
