require_relative './shared.rb'

def read_test_file(fname)
  base_read_test_file(fname)
end

def extract_format_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:code]
    text = text.split(' ').map do |char|
      [char.to_i(16)].pack('C')
    end.join
    File.open(output, 'wb') do |file|
      file << text
    end
  end
end

def disassemble(input, output, disasm_options)
  describe_action(input, output, 'disassemble') do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    cmd = "timeout 10 ./bin/cdisasm #{disasm_options} < #{input} > #{output}"
    psystem_noecho cmd
  end
end

def compare_files(file1, file2)
  body1 = File.read(file1)
  body2 = File.read(file2)

  if body1 != body2
    raise "Files #{file1} and #{file2} differ!"
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'
  test_prefix = settings[:test_output_prefix] || ''

  data = read_test_file(input)

  asm_input = data[:asm_input]

  options = data[:options] || ''
  with_headers = options['--with-headers']
  disasm_options = '--raw'
  disasm_options = '' if with_headers
  disasm_options = '--with-headers --no-numbers' if asm_input

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  in_asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.in.asm')).to_s
  asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.asm')).to_s
  bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.bin')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s
  post_bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.post.bin')).to_s
  FileUtils.rm(out) if File.exist?(out)

  if asm_input
    File.open(in_asm, 'wb') { |f| f << data[:asm_input] << "\n" }
    assemble(in_asm, bin)
  else
    extract_format_source(input, bin)
  end

  disassemble(bin, asm, disasm_options)

  expected = data[:expect].strip

  actual = File.read(asm).strip
  compare_output(info, actual, expected)

  if asm_input
    assemble(asm, post_bin)
    compare_files(bin, post_bin)
  end

  File.open(out, 'wb') { |f| f << '1' }
end

if $settings[:input].downcase.end_with? '.dat'
  run_test($settings)
end
