require_relative '../../setup'
require_relative '../shared/system'
require_relative '../shared/presence'
require_relative '../shared/debug_output'
require_relative '../shared/args_noautorun'
require_relative '../compiler/compiler_noautorun'
old_autorun = $autorun
$autorun = false
require_relative '../tobinary/tobinary'
$autorun = old_autorun

class DabCompareError < RuntimeError
end

class InlineCompilerExit < RuntimeError
  attr_reader :code

  def initialize(code)
    super()
    @code = code
  end
end

class InlineCompilerContext
  attr_reader :stdin, :stdout, :stderr

  def initialize
    @stdin = StringIO.new
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def exit(code)
    raise InlineCompilerExit.new(code)
  end
end

module BaseFrontend
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
      k = k.downcase.gsub(/[^a-z0-9]+/, '_').to_sym
      v = v.join("\n").strip
      [k, v]
    end.to_h
  end

  def describe_action(input, output, action)
    info = " * #{action}: #{input.to_s.blue.bold} -> #{output.blue.bold}..."
    warn info.white
    yield
    warn "#{info.white} #{'[OK]'.green}"
  end

  def describe_action_with_replacement(input, output, action, replacement)
    describe_action(input, output, action) do
      warn "~> #{replacement.yellow}"
      yield
    end
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
      cmd = "ruby src/#{tool}/#{tool}.rb #{options} #{input_part} #{input}"
      begin
        qsystem(cmd, timeout: 30, output_file: output)
      rescue SystemCommandError => e
        STDERR.puts
        warn e.stderr
        STDERR.puts
        raise
      end
    end
  end

  def compare_output(info, actual, expected, soft_match = false)
    expected ||= ''
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
      puts Diffy::Diff.new("#{expected}\n", "#{actual}\n").to_s(:color)
      puts "#{info}... ERROR!".red.bold
      raise DabCompareError.new('test error')
    end
  end

  def compile_dab_to_asm(input, output, options)
    options ||= ''
    input = [input].flatten
    context = InlineCompilerContext.new
    cmd_replacement = "ruby src/compiler/compiler.rb #{input.join(' ')} #{options}"
    describe_action_with_replacement(input, output, 'compile', cmd_replacement) do
      settings = options.split(' ') + input
      settings = read_args!(settings)
      run_dab_compiler(settings, context)
      File.open(output, 'wb') { |f| f << context.stdout.string }
    end
  rescue InlineCompilerExit
    err context.stderr.string
    raise SystemCommandError.new('Compile error', context.stderr.string)
  end

  def assemble(input, output, assemble_options = '')
    cmd_replacement = "ruby src/tobinary/tobinary.rb #{assemble_options} < #{input} > #{output}"
    describe_action_with_replacement(input, output, 'assemble', cmd_replacement) do
      input = File.open(input, 'r')
      output = File.open(output, 'wb')
      options = read_args!(assemble_options.split(' '))
      raw = options[:raw]
      run_tobinary(input, output, false, true, raw)
      input.close
      output.close
    end
  end

  def run_test(settings)
    @settings = settings
    run(@settings)
  end

  def input
    @settings[:input]
  end

  def test_output_dir
    @settings[:test_output_dir] || '.'
  end

  def test_prefix
    @settings[:test_output_prefix] || ''
  end

  def temp_file(extension)
    Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext(".#{extension}")).to_s
  end

  def write_new_testspec(filename, data)
    string = ''
    data.each do |key, value|
      string += "## #{key.to_s.tr('_', ' ').upcase}\n"
      string += "\n"
      string += value
      string += "\n"
      string += "\n"
    end
    File.open(filename, 'wb') do |file|
      file << string.strip
      file << "\n"
    end
  end
end

def disassemble(input, output, disasm_options = '')
  describe_action(input, output, 'disassemble') do
    input = input.to_s.shellescape
    output = output.to_s.shellescape
    cmd = "./bin/cdisasm #{disasm_options} #{input}"
    qsystem(cmd, output_file: output, timeout: 10)
  end
end
