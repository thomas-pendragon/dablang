require 'spec_helper'

require 'digest'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'
previous_autorun = defined?($autorun) ? $autorun : nil
$autorun = false
require_relative '../src/frontend/frontend_modern_source'
$autorun = previous_autorun

describe 'Modern explicit built-in to String conversion' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:source_unit) { DabSourceUnit.new(input: 'conversion.dabm', syntax_profile: DabSyntaxProfile::MODERN) }
  let(:numeric_types) { %w[Fixnum Int8 Int16 Int32 Int64 Uint8 Uint16 Uint32 Uint64] }

  around do |example|
    Dir.mktmpdir('dab-to-string') do |directory|
      @directory = directory
      example.run
    end
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def lower(source)
    parse(source).lower_into(DabNodeUnit.new)
  end

  def expect_error(source, message, offending, offset: nil)
    expect { lower(source) }.to raise_error(DabModernBootstrapParseError) do |error|
      expect(error.message).to eq(message)
      start = offset || source.index(offending)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    end
  end

  def compile(source, legacy: false)
    path = File.join(@directory, legacy ? 'program.dab' : 'program.dabm')
    File.binwrite(path, source)
    context = InlineCompilerContext.new
    status = 0
    begin
      profile = legacy ? DabSyntaxProfile::LEGACY : DabSyntaxProfile::MODERN
      settings = {inputs: [path]}
      settings[:ring_base] = [lower_ring] unless legacy
      run_dab_compiler(settings, context,
                       source_units: [DabSourceUnit.new(input: path, syntax_profile: profile)])
    rescue InlineCompilerExit => e
      status = e.code
    end
    [status, context.stdout.string.b, context.stderr.string]
  end

  def lower_ring
    @lower_ring ||= begin
      path = File.join(@directory, 'stdlib.dabcb')
      _output, error, status = Open3.capture3(
        RbConfig.ruby, File.join(root, 'src/frontend/frontend_stdlib.rb'), "--output=#{path}", chdir: root
      )
      expect(status.exitstatus).to eq(0), error
      path
    end
  end

  def assembly(source, legacy: false)
    status, output, error = compile(source, legacy: legacy)
    expect([status, error]).to eq([0, ''])
    output
  end

  def artifact(output)
    bytes, error, status = Open3.capture3(
      RbConfig.ruby, '-e', 'STDIN.binmode; STDOUT.binmode; load ARGV.shift',
      File.join(root, 'src/tobinary/tobinary.rb'), stdin_data: output, binmode: true, chdir: root
    )
    expect(status.exitstatus).to eq(0), error
    bytes
  end

  def execute(output)
    vm = File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}")
    skip 'native VM is built by the complete gate' unless File.executable?(vm)

    path = File.join(@directory, 'application.dabcb')
    File.binwrite(path, artifact(output))
    stdout, stderr, status = Open3.capture3(vm, lower_ring, path, binmode: true, chdir: root)
    [status.exitstatus, stdout.gsub("\r\n", "\n"), stderr]
  end

  it 'preserves callable to, to?, and String names and ordinary local identifiers' do
    source = <<~DAB
      def to():String
      return "to"
      end
      def to?():String
      return "to?"
      end
      def String():String
      return "String"
      end
      def main()
      let to = "local"
      let String = "target"
      print(to)
      print(String)
      print(to())
      print(to?())
      print(String())
      end
    DAB
    expect(assembly(source)).not_to include('MODERN_TO_STRING', 'to_s')
  end

  it 'keeps the second private syscall out of public source-callable registries' do
    expect(PRIVATE_KERNELCODES.fetch(0x0E)).to eq('MODERN_TO_STRING')
    expect(SYSCALLS).not_to include('__modern_to_string')
    expect(BUILTINS).not_to include('__modern_to_string')
    expect_error("def main()\n__modern_to_string(1)\nend\n",
                 'unknown Modern call target "__modern_to_string"', '__modern_to_string')
  end

  it 'admits every closed source type through parameters, returns, and ordinary arguments' do
    (numeric_types + %w[String NilClass Boolean]).each do |type|
      source = <<~DAB
        def converted(value:#{type}):String
        print(value to String)
        return value to String
        end
      DAB
      expect { lower(source) }.not_to raise_error, type
    end
  end

  it 'retains complete immutable source metadata without absorbing an enclosing argument delimiter' do
    source = "def main()\nprint(42 to String)\nend\n"
    value = parse(source).declarations.first.body_items.first.arguments.first
    expect(value).to be_a(DabModernBootstrapToString)
    expect(value).to be_frozen
    expect(value.source_tokens).to be_frozen
    expect(value.source_tokens.map(&:text).join).to eq('42 to String')
    expect(source.byteslice(value.source_span.start_offset...value.source_span.end_offset)).to eq('42 to String')
  end

  it 'admits literal, local, parameter, member-result, direct-call, and interpolated String atoms' do
    source = <<~'DAB'
      def producer():Int8
      return 255
      end
      def text(value:String):String
      let fixed = 42 to String
      let typed:String = true to String
      var mutable = nil to String
      var annotated:String = false to String
      mutable = 0 to String
      annotated = "#{value}" to String
      print(fixed to String)
      print(typed to String)
      print(mutable to String)
      print(annotated to String)
      print("abc".length to String)
      print("abc".length() to String)
      print(producer() to String)
      print(value to String)
      return producer() to String
      end
    DAB
    expect { lower(source) }.not_to raise_error
    output = assembly(source)
    expect(output).to match(/SYSCALL R\d+, 14, R\d+/)
    expect(output).not_to match(/SYSCALL RNIL, 14/)
  end

  it 'lowers non-identity conversion through one real-result private SYSCALL without public dispatch' do
    output = assembly("def value(actual:Int8):String\nreturn actual to String\nend\n")
    expect(output.scan(/SYSCALL R\d+, 14, R\d+\n/).length).to eq(1)
    expect(output).not_to include('to_s', 'CAST', 'INSTCALL')
    expect(output).to match(/SYSCALL (R\d+), 14, R\d+.*?SYSCALL (R\d+), 13, \1, R\d+\n\s+RETURN \2/m)
  end

  it 'erases identity conversion for literals, locals, parameters, calls, and recursive interpolation' do
    sources = [
      "def main()\nprint(\"text\"%s)\nend\n",
      "def main()\nlet value = \"text\"\nprint(value%s)\nend\n",
      "def main()\nlet value:String = nil\nprint(value%s)\nend\n",
      "def text(value:String):String\nreturn value%s\nend\n",
      "def text():String\nreturn \"text\"\nend\ndef main()\nprint(text()%s)\nend\n",
      "def text():String\nreturn nil\nend\ndef main()\nprint(text()%s)\nend\n",
      "def text(value:String):String\nreturn \"outer \#{\"inner \#{value}\"}\"%s\nend\n",
    ]
    sources.each do |source|
      expect(assembly(sprintf(source, ' to String'))).to eq(assembly(sprintf(source, '')))
    end
  end

  it 'requires exactly one ASCII space before and after contextual to' do
    ['  ', "\t", " \t"].each do |space|
      source = "def main()\nprint(1#{space}to String)\nend\n"
      expect_error(source, 'invalid Modern conversion: expected exactly one ASCII space before "to"', space)
      source = "def main()\nprint(1 to#{space}String)\nend\n"
      expect_error(source, 'invalid Modern conversion: expected exactly one ASCII space after "to"', space)
    end
    expect_error("def main()\nprint(\"x\"to String)\nend\n",
                 'invalid Modern conversion: expected exactly one ASCII space before "to"', 'to')
    source = "def main()\nprint(1 to)\nend\n"
    expect_error(source, 'invalid Modern conversion: expected exactly one ASCII space after "to"', ')',
                 offset: source.rindex(')'))
  end

  it 'requires an exact case-sensitive target with exact missing-target positions' do
    %w[string STRING Fixnum Object String? String!].each do |target|
      source = "def main()\nprint(1 to #{target})\nend\n"
      expect_error(source, 'invalid Modern conversion target: expected String', target)
    end
    source = "def main()\nprint(1 to )\nend\n"
    expect_error(source, 'invalid Modern conversion target: expected String', ')', offset: source.rindex(')'))
    ['print(1 to (String))', 'return 1 to (String)', 'let text = 1 to (String)'].each do |body|
      source = "def main()\n#{body}\nend\n"
      expect_error(source, 'invalid Modern conversion target: expected String', '(', offset: source.rindex('('))
    end
    source = "def main()\nprint(1 to ; )\nend\n"
    expect_error(source, 'invalid Modern conversion target: expected String', ';')
    source = "def main()\nreturn 1 to \nend\n"
    expect_error(source, 'invalid Modern conversion target: expected String', "\n", offset: source.index("\nend"))
  end

  it 'rejects a second contextual to on exactly the second token' do
    ['1 to String to String', '"x" to String to Boolean'].each do |value|
      source = "def main()\nprint(#{value})\nend\n"
      expect_error(source, 'unexpected Modern conversion: chained conversions are not supported', 'to',
                   offset: source.rindex('to'))
    end
  end

  it 'rejects unsupported source types on the complete atom span' do
    %w[IntPtr Float].each do |type|
      source = "def value(actual:#{type}):String\nreturn actual to String\nend\n"
      expect_error(source, "Modern conversion to String does not support #{type}", 'actual',
                   offset: source.rindex('actual'))
    end
    expect_error("def main()\nprint(/text/ to String)\nend\n",
                 'Modern conversion to String does not support Regex', '/text/')
    source = "def value()\nreturn 1\nend\ndef main()\nprint(value() to String)\nend\n"
    expect_error(source, 'Modern conversion to String does not support Object', 'value()',
                 offset: source.rindex('value()'))
  end

  it 'preflights the complete atom before target and source-type admission' do
    expect_error("def main()\nprint(missing() to Wrong)\nend\n",
                 'unknown Modern call target "missing"', 'missing')
    expect_error("def main()\nprint(missing() to (String))\nend\n",
                 'unknown Modern call target "missing"', 'missing')
    source = "def value(x:Int8):Float\nreturn nil\nend\ndef main()\nprint(value() to Wrong)\nend\n"
    expect_error(source, 'incorrect Modern call arity for "value": got 0, expected 1', 'value()',
                 offset: source.rindex('value()'))
    expect_error("def main()\nprint(/text/ to Wrong)\nend\n",
                 'invalid Modern conversion target: expected String', 'Wrong')
    source = "def main()\nprint(9223372036854775808 to Wrong)\nend\n"
    expect_error(source, 'Modern integer literal is outside supported range 0..9223372036854775807',
                 '9223372036854775808')
    source = "def main()\nprint(missing to Wrong)\nend\n"
    expect_error(source, DabModernBootstrapParseError::GENERIC_MESSAGE, 'missing')
    source = "def main()\nprint(\"abc\".missing to Wrong)\nend\n"
    expect_error(source, 'unknown Modern member target "String#missing"', 'missing')
    source = "def main()\nprint(\"\#{1}\" to Wrong)\nend\n"
    expect_error(source, 'cannot interpolate Modern expression of type Fixnum; EX-011 requires exact String', '1')
    source = "def main()\nlet value:String = /x/ to Wrong\nend\n"
    expect_error(source, 'invalid Modern conversion target: expected String', 'Wrong')
  end

  it 'checks conversion diagnostics and result assignability in each existing value slot' do
    slots = ['print(%s)', 'return %s', 'let text = %s', 'var text = %s', "var text = \"\"\ntext = %s"]
    slots.each do |slot|
      [
        ['1  to String', 'invalid Modern conversion: expected exactly one ASCII space before "to"', '  '],
        ['1 to  String', 'invalid Modern conversion: expected exactly one ASCII space after "to"', '  '],
        ['1 to string', 'invalid Modern conversion target: expected String', 'string'],
        ['/x/ to String', 'Modern conversion to String does not support Regex', '/x/'],
      ].each do |value, message, span|
        expect_error("def main()\n#{sprintf(slot, value)}\nend\n", message, span)
      end
    end
    expect_error("def main()\nlet value:Int8 = 1 to String\nend\n",
                 'cannot initialize Modern local "value" of type Int8 with literal of type String', '1 to String')
    expect_error("def main()\nvar value:Int8 = 1\nvalue = 1 to String\nend\n",
                 'cannot assign Modern literal of type String to local "value" of type Int8', '1 to String')
    expect_error("def main():Int8\nreturn 1 to String\nend\n",
                 'cannot return Modern value of type String from function "main" with declared return type Int8',
                 '1 to String')
  end

  it 'preserves print atom arity rules while accepting conversions in same-document String arguments' do
    output = assembly("def main()\nprint(1 to String, true to String, nil to String)\nend\n")
    expect(output.scan(/SYSCALL RNIL, 0, R\d+/).length).to eq(3)
    source = "def main(value:Fixnum)\nprint(value to String, 1 to String)\nend\n"
    expect_error(source, 'incorrect Modern call arity for "print": got 2, expected 1',
                 'print(value to String, 1 to String)')
    source = "def target(value:String)\nprint(value)\nend\ndef main()\ntarget(1 to String)\nend\n"
    expect { lower(source) }.not_to raise_error
  end

  it 'does not broaden local atoms, grouping, expressions, receivers, nesting, or interpolation splices' do
    values = [
      'let copy = value to String', 'var copy = value to String', 'value = value to String',
      'let copy = producer() to String', 'var copy = "a".length to String',
      'print((1 to String))', 'print(1 + 2 to String)', 'print(-1 to String)',
      'print(value.length to String)', 'print(producer(producer()) to String)',
      'print(1 to? String)', 'print(1 as String)', 'print(1 as? String)',
      'print(1 to String.length)', "print(\"\#{1 to String}\")",
      "print(\"\#{producer(1 to String)}\")", "print(\"\#{\"\#{1 to String}\"}\")",
      'if true to String', 'case 1 to String'
    ]
    values.each do |body|
      source = "def producer(value:Fixnum):Fixnum\nreturn value\nend\ndef main()\nvar value = 1\n#{body}\nend\n"
      expect { lower(source) }.to raise_error(DabModernBootstrapParseError), body
    end
  end

  it 'preserves the characterized parenthesized return diagnostic instead of recognizing a conversion' do
    ['return (1)', 'return (1 to String)'].each do |body|
      source = "def main()\n#{body}\nend\n"
      expect_error(source, DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE, ' ',
                   offset: source.index('return') + 6)
    end
    ['print((1 to String))', 'let text = (1 to String)', 'var text = (1 to String)'].each do |body|
      source = "def main()\n#{body}\nend\n"
      expect_error(source, DabModernBootstrapParseError::GENERIC_MESSAGE, '(',
                   offset: source.index('(1'))
    end
  end

  it 'preflights rejected conversions in dead source without publishing compiler stdout' do
    bodies = ["return\nprint(/x/ to String)", "if false\nprint(/x/ to String)\nend",
              "while false\nprint(/x/ to String)\nend", 'print(/x/ to String) if false']
    bodies.each do |body|
      status, output, error = compile("def main()\n#{body}\nend\n")
      expect([status, output]).to eq([2, ''])
      expect(error).to include('Modern conversion to String does not support Regex')
      expect(Dir.glob(File.join(@directory, '*.dabcb')).map { |path| File.basename(path) }).to eq(['stdlib.dabcb'])
    end
  end

  it 'keeps Legacy syntax and artifacts unchanged and the converter inaccessible to Legacy source' do
    source = 'func value<Int8>(actual<Int16>) { return actual; } func main() { print(value(255)); }'
    output = assembly(source, legacy: true)
    expect(Digest::SHA256.hexdigest(output)).to eq('18eeb2c7d5068023570bbe9ff9fc7ed557f198164cf471c4f5f865dc4ea7da1f')
    expect(Digest::SHA256.hexdigest(artifact(output))).to eq('ad479118e96c4ae05fddd6fa0865ab75f6c8b0828fd7db07170a2106c07f1195')
    status, stdout, _error = compile('func main() { __modern_to_string(1); }', legacy: true)
    expect([status, stdout]).to eq([1, ''])
  end

  it 'preserves every fixture golden through normal, reverse, and repeated compilation', :determinism do
    fixtures = Dir.glob(File.join(root, 'test/modern_source/*.dabmtest')).map { |path| DabModernSourceFixture.load(path) }
    compilations = [fixtures, fixtures.reverse, fixtures].map do |order|
      order.to_h do |fixture|
        source_path = File.join(@directory, fixture.source_filename)
        File.binwrite(source_path, fixture.source)
        result = DabModernSourceCompiler.new.compile(fixture, source_path: source_path, ring_base: lower_ring)
        expect([result.status, result.stdout, result.stderr]).to eq(
          [fixture.expected_status, fixture.expected_stdout, fixture.expected_stderr]
        ), fixture.path
        [fixture.path, result.stdout]
      end
    end
    fixture = fixtures.find { |entry| entry.path.include?('/0116_') }
    outputs = compilations.map { |result| result.fetch(fixture.path) }
    expect(outputs.uniq.length).to eq(1)
    expect(outputs.map { |output| artifact(output) }.uniq.length).to eq(1)
    expect(outputs.first).not_to include('to_s', 'TO_SYM')
    expect(outputs.first).not_to match(/SYSCALL RNIL, 14/)
    status, stdout, error = execute(outputs.first)
    expect([status, stdout]).to eq([0, fixture.expected_application_stdout]), error
  end

  it 'stops after earlier effects when a runtime argument violates its admitted static conversion type' do
    source = <<~DAB
      def text(value:Int16):String
      print("before\\n")
      return value to String
      end
      def main()
      print(text(1))
      print("later\\n")
      end
    DAB
    output = assembly(source).sub(/LOAD_ARG (R\d+), 0/, 'LOAD_FLOAT \1, 1.5')
    status, stdout, error = execute(output)
    expect([status, stdout]).to eq([1, "before\n"])
    expect(error.lines(chomp: true).grep(/vm: Modern/)).to eq(
      ['vm: Modern conversion to String does not support Float.']
    )
  end
end
