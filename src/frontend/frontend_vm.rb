require_relative './shared.rb'

def read_test_file(fname)
  base_read_test_file(fname)
end

def extract_format_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:code]
    File.open(output, 'wb') do |file|
      file << text
      file << "\n"
    end
  end
end

def assemble(input, output)
  run_ruby_part(input, output, 'assemble DabASM', 'tobinary')
end

def extract_vm_part(input, output, part, runoptions)
  describe_action(input, output, 'VM') do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    part = part.to_s.shellescape
    flags = '--raw'
    flags = '' if runoptions['--noraw']
    cmd = "timeout 10 ./bin/cvm #{flags} --output=#{part} < #{input} > #{output}"
    psystem_noecho cmd
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'
  test_prefix = settings[:test_output_prefix] || ''

  data = read_test_file(input)

  runoptions = data[:runoptions] || ''

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.asm')).to_s
  bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.bin')).to_s
  out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s
  FileUtils.rm(out) if File.exist?(out)

  extract_format_source(input, asm)
  assemble(asm, bin)

  testcase = data[:testcase]
  expected = data[:expect]

  index = 0
  testcase.gsub!(/\$([^\s]+)/) do |_match|
    output = $1
    part = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext(".part#{index}")).to_s
    index += 1
    extract_vm_part(bin, part, output, runoptions)
    File.open(part).read.strip
  end

  compare_output(info, testcase, expected)

  File.open(out, 'wb') { |f| f << '1' }
end

if $settings[:input].downcase.end_with? '.vmt'
  run_test($settings)
end
