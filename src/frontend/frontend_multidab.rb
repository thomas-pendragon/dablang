require_relative './shared_noautorun'

$autorun = true if $autorun.nil?

class DabMultiSpec
  include BaseFrontend

  def read_test_file(fname)
    base_read_test_file(fname)
  end

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

    level = 0
    last_vmo = nil

    all_bin = []

    out = temp_file('out')

    begin
      sym = "level_#{level}".to_sym
      next_sym = "level_#{level + 1}".to_sym
      is_final = !data[next_sym]

      lfile = "level#{level}"
      dab = temp_file("#{lfile}.dab")
      asm = temp_file("#{lfile}.dabca")
      bin = temp_file("#{lfile}.dabcb")
      bin_asm = temp_file("#{lfile}.dabcb.dabca")
      vmo = temp_file("#{lfile}.vm")
      vmoa = temp_file("#{lfile}.vm.dabca")

      extract_source(input, dab, data[sym])
      compile_options = ''
      all_bin.each do |base|
        compile_options += " --ring-base[]=#{base}"
      end
      compile_dab_to_asm(dab, asm, compile_options)
      assemble_options = ''
      assemble(asm, bin, assemble_options)
      disassemble(bin, bin_asm, '--with-headers')
      run_options = "--entry=level#{level}"
      unless is_final
        run_options += ' --output=dumpvm'
      end
      run_options += ' --verbose'
      execute(all_bin + [bin], vmo, run_options)

      all_bin << vmo unless is_final

      unless is_final
        disassemble(vmo, vmoa, '--with-headers')
      end

      level += 1
      last_vmo = vmo
    end until is_final

    test_body = data[:expect]
    actual_body = File.read(last_vmo).strip
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

  test = DabMultiSpec.new
  test.run_test($settings)
end
