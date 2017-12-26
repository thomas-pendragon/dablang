require_relative './shared_noautorun.rb'

$autorun = true if $autorun.nil?

class VMFrontend
  include BaseFrontend

  def read_test_file(fname)
    base_read_test_file(fname)
  end

  def extract_format_source(input, output, source = :code)
    describe_action(input, output, 'extract source') do
      text = read_test_file(input)[source]
      File.open(output, 'wb') do |file|
        file << text
        file << "\n"
      end
    end
  end

  def extract_vm_part(input, output, part, flags)
    describe_action(input, output, 'VM') do
      input = input.to_s
      output = output.to_s
      part = part.to_s
      cmd = "./bin/cvm #{flags} --output=#{part}"
      qsystem(cmd, input_file: input, output_file: output, timeout: 10)
    end
  end

  def run(_settings)
    data = read_test_file(input)

    options = data[:options] || ''

    raw = options['--raw']
    noraw = options['--noraw']
    nomain = options['--nomain']

    raise 'must specify either --raw, --nomain or --noraw' unless raw || noraw || nomain

    noautorelease = options['--noautorelease']

    assemble_options = ''
    assemble_options += '--raw ' if raw

    runoptions = ''
    runoptions += '--bare ' if raw
    runoptions += '--raw ' if nomain || raw
    runoptions += '--noautorelease ' if noautorelease

    info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
    puts info
    FileUtils.mkdir_p(test_output_dir)

    dab = temp_file('dab')
    asm = temp_file('asm')
    bin = temp_file('bin')
    out = temp_file('out')
    FileUtils.rm(out) if File.exist?(out)

    if data[:dab_code]
      compile_options = ''
      extract_format_source(input, dab, :dab_code)
      compile_dab_to_asm([dab], asm, compile_options)
    else
      extract_format_source(input, asm)
    end

    assemble(asm, bin, assemble_options)

    testcase = data[:testcase]
    expected = data[:expect]

    index = 0
    testcase.gsub!(/\$([^\s]+)/) do |_match|
      output = $1
      part = temp_file("part#{index}")
      extract_vm_part(bin, part, output, runoptions)
      chunk = File.open(part).read
      if output == 'dumpvm'
        part_bin = temp_file("part#{index}.bin")
        part_asm = temp_file("part#{index}.asm")
        File.open(part_bin, 'wb') { |f| f << chunk }
        disassemble(part_bin, part_asm, '--with-headers --no-numbers')
        chunk = File.read(part_asm)
      end
      index += 1
      chunk.strip
    end

    compare_output(info, testcase, expected)

    File.open(out, 'wb') { |f| f << '1' }
  end
end

if $autorun
  read_args!
  raise 'no vmt' unless $settings[:input].downcase.end_with?('.vmt')
  test = VMFrontend.new
  test.run_test($settings)
end
