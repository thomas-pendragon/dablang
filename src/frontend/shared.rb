require_relative '../shared/system.rb'
require 'colorize'
require 'pathname'
require 'rake'
require 'shellwords'
require 'fileutils'

class DabCompareError < RuntimeError
end

args = ARGV.dup
flag = nil
$settings = {}

while args.count > 0
  arg = args.shift
  if flag.nil?
    if arg.start_with? '--'
      flag = arg[2..-1].to_sym
    else
      $settings[:input] = arg
    end
  else
    $settings[flag] = arg
    flag = nil
  end
end

raise 'no input' unless $settings[:input]

def read_test_file(fname)
  text = ''
  test_body = ''
  compile_error = ''
  mode = nil
  input = ''
  options = ''
  output = ''
  expected_status = nil
  open(fname).read.split("\n").each do |line|
    if line.start_with? '## '
      mode = line.strip
    elsif mode == '## CODE'
      text += line.strip + "\n"
    elsif mode == '## INPUT'
      input += line + "\n"
    elsif mode == '## OPTIONS'
      options += line + "\n"
    elsif mode == '## OUTPUT'
      output += line + "\n"
    elsif mode == '## EXPECT COMPILE ERROR'
      expected_status = :compile_error
      compile_error += line.strip + "\n"
    elsif mode == '## EXPECT OK'
      expected_status = :ok
      test_body += line.strip + "\n"
    end
  end
  data = [text, test_body, input, options, output].map(&:strip)
  {
    input: data[2],
    options: data[3],
    output: data[4],
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

def run_ruby_part(input, output, action, tool, options = '')
  describe_action(input, output, action) do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    options = options.to_s.shellescape
    cmd = "timeout 10 ruby src/#{tool}/#{tool}.rb #{options} < #{input} > #{output}"
    begin
      psystem_noecho cmd
    rescue SystemCommandError => e
      STDERR.puts
      STDERR.puts e.stderr
      STDERR.puts
      raise
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
    raise DabCompareError.new('test error')
  end
end
