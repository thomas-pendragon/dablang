require_relative '../shared/system.rb'
require 'colorize'
require 'pathname'
require 'rake'
require 'shellwords'
require 'fileutils'

args = ARGV.dup
flag = nil
settings = {}

while args.count > 0
  arg = args.shift
  if flag.nil?
    if arg.start_with? '--'
      flag = arg[2..-1].to_sym
    else
      settings[:input] = arg
    end
  else
    settings[flag] = arg
    flag = nil
  end
end

raise 'no input' unless settings[:input]

def read_test_file(fname)
  text = ''
  test_body = ''
  mode = nil
  open(fname).read.split("\n").map(&:strip).each do |line|
    if line.start_with? '## '
      mode = line
    elsif mode == '## CODE'
      text += line + "\n"
    elsif mode == '## EXPECT OK'
      test_body += line + "\n"
    end
  end
  data = [text, test_body].map(&:strip)
  {code: data[0], expected_status: true, expected_body: data[1]}
end

def describe_action(input, output, action)
  info = " * #{action}: #{input.blue.bold} -> #{output.blue.bold}..."
  puts info.white
  yield
  puts "#{info.white} #{'[OK]'.green}"
end

def run_ruby_part(input, output, action, tool)
  describe_action(input, output, action) do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    cmd = "ruby src/#{tool}/#{tool}.rb < #{input} > #{output}"
    psystem_noecho cmd
  end
end

def compile_to_asm(input, output)
  run_ruby_part(input, output, 'compile to DabASM', 'compiler')
end

def assemble(input, output)
  run_ruby_part(input, output, 'assemble DabASM', 'tobinary')
end

def execute(input, output)
  run_ruby_part(input, output, 'run', 'vm')
end

def extract_source(input, output)
  describe_action(input, output, 'extract source') do
    text = read_test_file(input)[:code]
    File.open(output, 'wb') do |file|
      file << text
    end
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)
  dab = Pathname.new(test_output_dir).join(File.basename(input).ext('.dab')).to_s
  extract_source(input, dab)
  asm = Pathname.new(test_output_dir).join(File.basename(input).ext('.dabca')).to_s
  compile_to_asm(dab, asm)
  bin = Pathname.new(test_output_dir).join(File.basename(input).ext('.dabcb')).to_s
  assemble(asm, bin)
  out = Pathname.new(test_output_dir).join(File.basename(input).ext('.out')).to_s
  execute(bin, out)

  test_body = read_test_file(input)[:expected_body]

  actual_body = open(out).read.strip
  if actual_body == test_body
    puts "#{info}... OK!".green
  else
    puts 'Expected:'.bold
    puts test_body
    puts 'Received:'.bold
    puts actual_body
    puts "#{info}... ERROR!".red.bold
    raise 'test error'
  end
end

if settings[:input].downcase.end_with? '.dabt'
  run_test(settings)
end
