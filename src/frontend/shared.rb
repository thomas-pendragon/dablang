require_relative '../../setup.rb'
require_relative '../shared/system.rb'
require_relative '../shared/presence.rb'
require_relative '../shared/debug_output.rb'
require_relative '../shared/args.rb'

class DabCompareError < RuntimeError
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
  info = " * #{action}: #{input.to_s.blue.bold} -> #{output.blue.bold}..."
  puts info.white
  yield
  puts "#{info.white} #{'[OK]'.green}"
end

def run_ruby_part(input, output, action, tool, options = '', input_as_arg = false)
  describe_action(input, output, action) do
    if input.is_a? Array
      raise 'must input as arg' unless input_as_arg
      input = input.map(&:to_s).map(&:shellescape).join(' ')
    else
      input = input.to_s.shellescape
    end
    output = output.to_s.shellescape
    options = options.presence
    options = options.to_s if options
    input_part = input_as_arg ? ' ' : '<'
    cmd = "timeout 10 ruby src/#{tool}/#{tool}.rb #{options} #{input_part} #{input} > #{output}"
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
            actual.uncolorize.include? expected.uncolorize
          else
            actual.uncolorize == expected.uncolorize
          end
  if match
    puts "#{info}... OK!".green
  else
    puts 'Received:'.bold
    puts actual
    Clipboard.copy(actual)
    puts 'Expected:'.bold
    puts expected
    puts 'Diff:'.bold
    puts Diffy::Diff.new(expected + "\n", actual + "\n").to_s(:color)
    puts "#{info}... ERROR!".red.bold
    raise DabCompareError.new('test error')
  end
end
