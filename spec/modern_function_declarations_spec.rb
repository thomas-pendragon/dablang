require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern top-level function declarations' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'functions.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def invoke(*command, input: nil)
    Open3.capture3(*command, stdin_data: input, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq([0, "PASS #{artifact}\n"])
    expect(stderr).not_to include('exception:', 'FAILED')
    artifact
  end

  def compile_modern(directory, lower:, basename:, source:)
    path = File.join(directory, "#{basename}.dabm")
    File.binwrite(path, source)
    [*invoke(RbConfig.ruby, compiler, path, "--ring-base[]=#{lower}"), path]
  end

  it 'parses and lowers distinct plain and suffixed declarations in source order' do
    document = parse(
      ";def worker;nil;end;# between\n" \
      "def ready?// header\ntrue\nend// close\n" \
      "def save!\n\"saved\"\nend\n"
    )

    expect(document.declarations.map { |declaration| declaration.callable_name.text })
      .to eq(%w[worker ready? save!])
    expect(document.declarations.map { |declaration| declaration.body_tokens.map(&:kind) })
      .to eq([[:nil], [:boolean_true], [:string]])
    expect(document.declarations.map { |declaration| declaration.callable_name.source_span.start_offset })
      .to eq([5, 34, 71])

    unit = DabNodeUnit.new
    functions = document.lower_into(unit)

    expect(functions.map(&:identifier)).to eq(%w[worker ready? save!])
    expect(functions).to all(satisfy { |function| function.arglist.empty? })
    expect(unit.functions.map(&:identifier)).to eq(%w[worker ready? save!])
  end

  it 'treats plain, question, and bang composite names as distinct' do
    document = parse("def ready\nend\ndef ready?\nend\ndef ready!\nend\n")
    unit = DabNodeUnit.new

    functions = document.lower_into(unit)

    expect(functions.map(&:identifier)).to eq(%w[ready ready? ready!])
    expect(unit.has_function?('ready')).to equal(functions.fetch(0))
    expect(unit.has_function?('ready?')).to equal(functions.fetch(1))
    expect(unit.has_function?('ready!')).to equal(functions.fetch(2))
  end

  it 'preflights every name and leaves the unit untouched on a same-document collision' do
    document = parse("def first\nend\ndef duplicate?\nend\ndef duplicate?\nend\n")
    unit = DabNodeUnit.new

    expect do
      document.lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([37, 47])
      expect(error.source_span.source_unit).to equal(source_unit)
    }
    expect(unit.functions).to be_empty
    expect(unit.has_function?('first')).to be_nil
  end

  it 'preflights builtins before adding any declaration' do
    document = parse("def first\nend\ndef print\nend\n")
    unit = DabNodeUnit.new

    expect do
      document.lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([18, 23])
    }
    expect(unit.functions).to be_empty
  end

  it 'uses the same eight structural diagnostics for arbitrary callable names' do
    cases = [
      ['def', DabModernBootstrapParser::EXPECT_SPACE_MESSAGE, [3, 3]],
      ['def ', DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE, [4, 4]],
      ['def worker', DabModernBootstrapParser::EXPECT_NAME_SEPARATOR_MESSAGE, [10, 10]],
      ["def worker\nnil", DabModernBootstrapParser::EXPECT_LITERAL_SEPARATOR_MESSAGE, [14, 14]],
      ["def worker\n", DabModernBootstrapParser::EXPECT_END_MESSAGE, [11, 11]],
      ["def worker\nend", DabModernBootstrapParser::EXPECT_END_SEPARATOR_MESSAGE, [14, 14]],
      ["end\n", DabModernBootstrapParser::UNEXPECTED_END_MESSAGE, [0, 3]],
      ["def worker\r\nend\r\n", DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE, [10, 12]],
    ]

    cases.each do |source, message, span|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message)
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(span)
      }
    end
  end

  it 'reports collisions transactionally through the compiler after parsing the complete document' do
    Dir.mktmpdir('dab-modern-function-collisions') do |directory|
      lower = build_stdlib(directory)
      cases = {
        'same-document' => ["def kept\nend\ndef kept\nend\n", 3, 4],
        'builtin' => ["def kept\nend\ndef print\nend\n", 3, 4],
        'lower-ring' => ["def kept\nend\ndef puts\nend\n", 3, 4],
      }

      cases.each do |basename, (source, line, column)|
        stdout, stderr, status, path = compile_modern(
          directory,
          lower: lower,
          basename: basename,
          source: source
        )

        expect([status.exitstatus, stdout]).to eq([2, '']), basename
        expect(tool_stderr(stderr)).to eq(
          "compiler: #{path}:#{line}:#{column}: error: " \
          "#{DabModernBootstrapParseError::GENERIC_MESSAGE}\n"
        ), basename
      end
    end
  end

  it 'reports a later structural failure before an earlier duplicate collision' do
    Dir.mktmpdir('dab-modern-function-parse-first') do |directory|
      lower = build_stdlib(directory)
      stdout, stderr, status, path = compile_modern(
        directory,
        lower: lower,
        basename: 'parse-first',
        source: "def repeated\nend\ndef repeated\nend\ndef broken"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{path}:5:10: error: " \
        "#{DabModernBootstrapParser::EXPECT_NAME_SEPARATOR_MESSAGE}\n"
      )
    end
  end

  it 'emits byte-identical sorted assembly for both declaration orders' do
    forward = "def main\nnil\nend\ndef ready?\ntrue\nend\ndef save!\n\"saved\"\nend\n"
    reverse = "def save!\n\"saved\"\nend\ndef ready?\ntrue\nend\ndef main\nnil\nend\n"

    Dir.mktmpdir('dab-modern-function-order') do |directory|
      lower = build_stdlib(directory)
      forward_stdout, forward_stderr, forward_status, = compile_modern(
        directory,
        lower: lower,
        basename: 'forward',
        source: forward
      )
      reverse_stdout, reverse_stderr, reverse_status, = compile_modern(
        directory,
        lower: lower,
        basename: 'reverse',
        source: reverse
      )

      expect([forward_status.exitstatus, tool_stderr(forward_stderr)]).to eq([0, ''])
      expect([reverse_status.exitstatus, tool_stderr(reverse_stderr)]).to eq([0, ''])
      expect(reverse_stdout).to eq(forward_stdout)
      expect(forward_stdout).to include('Fmain:', 'Fready%QUEST:', 'Fsave%BANG:')
    end
  end

  it 'executes every plain and suffixed entry through the unchanged native VM' do
    expect(File).to exist(vm)

    source = "def main\nnil\nend\ndef ready?\ntrue\nend\ndef save!\n\"saved\"\nend\n"
    Dir.mktmpdir('dab-modern-function-entries') do |directory|
      lower = build_stdlib(directory)
      assembly, compiler_stderr, compiler_status, = compile_modern(
        directory,
        lower: lower,
        basename: 'entries',
        source: source
      )
      expect([compiler_status.exitstatus, tool_stderr(compiler_stderr)]).to eq([0, ''])

      bytecode, assembler_stderr, assembler_status = invoke(
        RbConfig.ruby,
        assembler,
        input: assembly
      )
      expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq([0, ''])
      upper = File.join(directory, 'entries.dabcb')
      File.binwrite(upper, bytecode)

      %w[main ready? save!].each do |entry|
        application_output = File.join(directory, "#{entry.tr('?!', 'qb')}.out")
        stdout, stderr, status = invoke(
          vm,
          "--entry=#{entry}",
          "--out=#{application_output}",
          lower,
          upper
        )

        expect([status.exitstatus, stdout, File.binread(application_output)]).to eq([0, '', '']), entry
        expect(stderr).not_to match(/error|failed|sanitizer|warning/i), entry
      end
    end
  end
end
