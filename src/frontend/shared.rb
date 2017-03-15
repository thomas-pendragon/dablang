require_relative '../shared/system.rb'
require_relative '../shared/presence.rb'
require_relative '../shared/debug_output.rb'
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

def base_read_test_file(fname)
  ret = {}
  mode = nil
  open(fname).read.split("\n").each do |line|
    if line.start_with? '## '
      mode = line[2..-1].strip
      ret[mode] ||= []
    else
      ret[mode] << line
    end
  end
  ret.map do |k, v|
    k = k.downcase.gsub(/[^a-z]+/, '_').to_sym
    v = v.join("\n").strip
    [k, v]
  end.to_h
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
