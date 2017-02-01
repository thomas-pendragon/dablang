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
  compile_error = ''
  mode = nil
  expected_status = nil
  open(fname).read.split("\n").map(&:strip).each do |line|
    if line.start_with? '## '
      mode = line
    elsif mode == '## CODE'
      text += line + "\n"
    elsif mode == '## EXPECT COMPILE ERROR'
      expected_status = :compile_error
      compile_error += line + "\n"
    elsif mode == '## EXPECT OK'
      expected_status = :ok
      test_body += line + "\n"
    end
  end
  data = [text, test_body].map(&:strip)
  {
    code: data[0],
    expected_status: expected_status,
    expected_body: data[1],
    expected_compile_error: compile_error.strip,
  }
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

def compare_output(info, actual, expected, soft_match = false)
  match = if soft_match
            actual.include? expected
          else
            actual == expected
          end
  if match
    puts "#{info}... OK!".green
  else
    puts 'Received:'.bold
    puts actual
    puts 'Expected:'.bold
    puts expected
    puts "#{info}... ERROR!".red.bold
    raise 'test error'
  end
end

def run_test(settings)
  input = settings[:input]
  test_output_dir = settings[:test_output_dir] || '.'

  data = read_test_file(input)

  info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
  puts info
  FileUtils.mkdir_p(test_output_dir)

  dab = Pathname.new(test_output_dir).join(File.basename(input).ext('.dab')).to_s
  asm = Pathname.new(test_output_dir).join(File.basename(input).ext('.dabca')).to_s
  bin = Pathname.new(test_output_dir).join(File.basename(input).ext('.dabcb')).to_s
  out = Pathname.new(test_output_dir).join(File.basename(input).ext('.out')).to_s

  extract_source(input, dab)
  begin
    compile_to_asm(dab, asm)
  rescue SystemCommandError => e
    if data[:expected_status] == :compile_error
      compare_output('compare compiler output', e.stderr, data[:expected_compile_error], true)
      FileUtils.touch(out)
      return
    else
      raise e
    end
  end
  if data[:expected_status] == :compile_error
    raise "Expected compiler error in #{input}"
  end
  assemble(asm, bin)
  execute(bin, out)

  test_body = data[:expected_body]
  actual_body = open(out).read.strip
  compare_output(info, actual_body, test_body)
end

if settings[:input].downcase.end_with? '.dabt'
  run_test(settings)
end
