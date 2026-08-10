require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'
previous_autorun = defined?($autorun) ? $autorun : nil
$autorun = false
require_relative '../src/frontend/frontend_modern_source'
$autorun = previous_autorun

describe 'Modern bare return' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'bare-return.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def invoke(*command, input: nil)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-bundler')}
    Open3.capture3(environment, *command, stdin_data: input, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def expect_parse_error(source, message, offending, offset: source.index(offending))
    expect do
      parse(source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [offset, offset + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq([0, "PASS #{artifact}\n"])
    expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')
    artifact
  end

  def compile(source_path, lower)
    assembly, stderr, status = invoke(
      RbConfig.ruby,
      compiler,
      source_path,
      "--ring-base[]=#{lower}"
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    assembly
  end

  def assemble(directory, assembly, basename)
    bytecode, stderr, status = invoke(RbConfig.ruby, assembler, input: assembly)
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    File.join(directory, "#{basename}.dabcb").tap { |path| File.binwrite(path, bytecode) }
  end

  it 'scans only exact lowercase ASCII return as a frozen keyword with exact source metadata' do
    source = 'return Return returns return1 _return'.b
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end
    words = tokens.reject { |token| %i[space eof].include?(token.kind) }

    expect(words.map { |token| [token.kind, token.text, token.value] }).to eq(
      [
        [:return, 'return', 'return'],
        [:identifier, 'Return', 'Return'],
        [:identifier, 'returns', 'returns'],
        [:identifier, 'return1', 'return1'],
        [:identifier, '_return', '_return'],
      ]
    )
    keyword = words.fetch(0)
    expect([keyword.source_span.start_offset, keyword.source_span.end_offset]).to eq([0, 6])
    expect(keyword.source_span.source_unit).to equal(source_unit)
    expect(keyword.source_string.to_s).to eq('return')
    expect(keyword).to be_frozen
  end

  it 'builds a frozen keyword-only wrapper and lowers through the existing Nil return' do
    source = "def main()\n  return\nend\n"
    document = parse(source)
    bare_return = document.declarations.fetch(0).body_items.fetch(0)
    keyword_offset = source.index('return')

    expect(bare_return).to be_a(DabModernBootstrapBareReturn)
    expect(bare_return.kind).to eq(:bare_return)
    expect(bare_return).to be_frozen
    expect(bare_return.instance_variables).to contain_exactly(:@keyword_token, :@source_parts, :@source_span)
    expect(bare_return.source_parts.map(&:to_s)).to eq(['return'])
    expect([bare_return.source_span.start_offset, bare_return.source_span.end_offset]).to eq(
      [keyword_offset, keyword_offset + 6]
    )

    function = document.lower_into(DabNodeUnit.new)
    lowered = function.blocks[0].all_nodes(DabNodeReturn).fetch(0)
    expect(lowered.value).to be_a(DabNodeLiteralNil)
    expect([lowered.source_cstart, lowered.source_cend]).to eq([keyword_offset, keyword_offset + 6])
    expect(lowered.all_nodes(DabNodeLocalVar)).to be_empty
  end

  it 'accepts only LF, semicolon, and adjacent line comments without consuming indentation' do
    source = <<~DAB
      def main()
        return
      end
      def semicolon();return;end
      def hash()
      return# adjacent
      end
      def slash()
      return// adjacent
      end
    DAB
    declarations = parse(source).declarations

    expect(declarations.map { |declaration| declaration.body_items.map(&:kind) }).to eq(
      [[:bare_return], [:bare_return], [:bare_return], [:bare_return]]
    )
    expect(declarations.flat_map(&:body_items)).to all(be_frozen)
  end

  it 'rejects every other separator and line-ending boundary at the closed span' do
    message = DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE
    cases = {
      'space before LF' => ["def main()\nreturn \nend\n", ' '],
      'TAB before LF' => ["def main()\nreturn\t\nend\n", "\t"],
      'value' => ["def main()\nreturn value\nend\n", ' '],
      'integer' => ["def main()\nreturn 1\nend\n", ' '],
      'direct call' => ["def main()\nreturn()\nend\n", '('],
      'question suffix' => ["def main()\nreturn?()\nend\n", '?'],
      'bang suffix' => ["def main()\nreturn!()\nend\n", '!'],
      'dot' => ["def main()\nreturn.\nend\n", '.'],
      'equal' => ["def main()\nreturn=1\nend\n", '='],
    }
    cases.each_value do |source, offending|
      offset = source.index(offending, source.index('return') + 6)
      expect_parse_error(source, message, offending, offset: offset)
    end

    eof_source = "def main()\nreturn"
    expect_parse_error(eof_source, message, '', offset: eof_source.bytesize)

    ["\r", "\r\n"].each do |ending|
      direct = "def main()\nreturn#{ending}end\n"
      expect_parse_error(
        direct,
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        ending,
        offset: direct.index(ending)
      )

      after_space = "def main()\nreturn #{ending}end\n"
      expect_parse_error(
        after_space,
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        ending,
        offset: after_space.index(ending)
      )
    end
  end

  it 'globally reserves return with each production-specific existing diagnostic and span' do
    cases = {
      'function name' => [
        "def return()\nend\n",
        DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE,
      ],
      'first parameter' => [
        "def f(return:Int32)\nend\n",
        DabModernBootstrapParser::EXPECT_PARAMETER_OR_CLOSE_MESSAGE,
      ],
      'later parameter' => [
        "def f(a:Int32,return:String)\nend\n",
        DabModernBootstrapParser::EXPECT_PARAMETER_AFTER_COMMA_MESSAGE,
      ],
      'let name' => [
        "def main()\nlet return = 1\nend\n",
        DabModernBootstrapParser::EXPECT_LET_NAME_MESSAGE,
      ],
      'var name' => [
        "def main()\nvar return = 1\nend\n",
        DabModernBootstrapParser::EXPECT_VAR_NAME_MESSAGE,
      ],
      'member name' => [
        "def main()\n\"x\".return()\nend\n",
        DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE,
      ],
      'first argument' => [
        "def main()\nprint(return)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ],
      'later argument' => [
        "def main()\nprint(1,return)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE,
      ],
      'parameter type' => [
        "def f(a:return)\nend\n",
        DabModernBootstrapParser::EXPECT_PARAMETER_TYPE_MESSAGE,
      ],
      'return type' => [
        "def f():return\nend\n",
        DabModernBootstrapParser::EXPECT_RETURN_TYPE_MESSAGE,
      ],
      'local type' => [
        "def main()\nlet value:return = 1\nend\n",
        DabModernBootstrapParser::EXPECT_LOCAL_TYPE_MESSAGE,
      ],
      'initializer' => [
        "def main()\nlet value = return\nend\n",
        DabModernBootstrapParseError::GENERIC_MESSAGE,
      ],
      'top level' => [
        "return\n",
        DabModernBootstrapParseError::GENERIC_MESSAGE,
      ],
    }
    cases.each_value do |source, message|
      expect_parse_error(source, message, 'return')
    end
  end

  it 'keeps case variants and longer spellings as identifiers while Legacy behavior is unchanged' do
    %w[Return returns return1 _return].each do |name|
      source = "def #{name}()\nend\ndef main()\n#{name}()\nend\n"
      expect(parse(source).lower_into(DabNodeUnit.new).map(&:identifier)).to eq([name, 'main'])
    end

    legacy_unit = DabSourceUnit.new(input: 'legacy.dab', syntax_profile: DabSyntaxProfile::LEGACY)
    legacy_scanner = DabScanner.new('return', source_unit: legacy_unit)
    start_location = legacy_scanner.current_location
    legacy_scanner.advance!(6)
    legacy_span = legacy_scanner.source_span(0, 6)
    expect(legacy_span.start_location.to_h).to eq(start_location.to_h)
    expect(legacy_span.end_location.to_h).to eq(offset: 6, line: 1, column: 6)
  end

  it 'parses the complete dead tail before source-ordered local preflight' do
    structural_tail = <<~DAB
      def main()
      let fixed = 1
      fixed = 2
      return
      print(,)
      end
    DAB
    expect do
      parse(structural_tail)
    end.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    local_tail = <<~DAB
      def main()
      return
      let value : String = 1
      end
    DAB
    expect do
      parse(local_tail)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot initialize Modern local "value" of type String with literal of type Fixnum'
      )
      expect(local_tail.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq('1')
    }

    later_declaration = "def main()\nreturn\nend\ndef return()\nend\n"
    expect_parse_error(
      later_declaration,
      DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE,
      'return',
      offset: later_declaration.rindex('return')
    )
  end

  it 'keeps name and call preflight after local validation and commits no partial unit' do
    document = parse("def helper()\nreturn\nmissing()\nend\ndef main()\nhelper()\nend\n")
    unit = DabNodeUnit.new
    original_functions = unit.functions.to_a

    expect do
      document.lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError, 'unknown Modern call target "missing"')
    expect(unit.functions.to_a).to eq(original_functions)

    colliding = DabNodeUnit.new
    existing = DabNodeFunction.new('helper', DabNodeTreeBlock.new, DabNode.new)
    colliding.add_function(existing)
    expect do
      parse("def helper()\nreturn\nend\n").lower_into(colliding)
    end.to raise_error(DabModernBootstrapParseError)
    expect(colliding.functions.to_a).to eq([existing])
  end

  it 'reports structural and local dead-tail failures before lower-Ring I/O' do
    cases = {
      'structure' => [
        "def main()\nreturn\nprint(,)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
        3,
      ],
      'local' => [
        "def main()\nreturn\nlet value:String = 1\nend\n",
        'cannot initialize Modern local "value" of type String with literal of type Fixnum',
        3,
      ],
    }

    Dir.mktmpdir('dab-modern-bare-return-preflight') do |directory|
      missing_ring = File.join(directory, 'missing.dabcb')
      cases.each do |description, (source, message, line)|
        source_path = File.join(directory, "#{description}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{missing_ring}"
        )

        expect([status.exitstatus, stdout]).to eq([2, '']), description
        expect(tool_stderr(stderr)).to include(
          "compiler: #{source_path}:#{line}:",
          "error: #{message}"
        ), description
        expect(File).not_to exist(missing_ring)
      end
    end
  end

  it 'eliminates the complete dead tail deterministically and allocates no return register' do
    Dir.mktmpdir('dab-modern-bare-return-assembly') do |directory|
      lower = build_stdlib(directory)
      compact_path = File.join(directory, 'compact.dabm')
      tailed_path = File.join(directory, 'tailed.dabm')
      compact = <<~DAB
        def helper()
        print("before\\n")
        return
        end
        def main()
        helper()
        return
        end
      DAB
      tailed = compact.sub("return\nend\ndef main", "return\nprint(\"after\\n\")\nvar tail = 1\nprint(tail)\nend\ndef main")
      tailed = tailed.sub("return\nend\n", "return\nprint(\"main-after\\n\")\nend\n")
      File.binwrite(compact_path, compact)
      File.binwrite(tailed_path, tailed)

      compact_assembly = compile(compact_path, lower)
      tailed_assembly = compile(tailed_path, lower)
      expect(tailed_assembly).to eq(compact_assembly)
      expect(tailed_assembly).to include('W_STRING "before')
      expect(tailed_assembly).not_to include('after', 'main-after', 'LOAD_NUMBER')
      expect(tailed_assembly.lines.grep(/RETURN RNIL/).length).to eq(3)
      expect(tailed_assembly).not_to match(/RETURN R\d/)
    end
  end

  it 'exits helper, main, and a selected custom entry with Nil and resumes only callers', :native do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-bare-return-runtime') do |directory|
      lower = build_stdlib(directory)
      source_path = File.join(directory, 'runtime.dabm')
      fixture = DabModernSourceFixture.load(
        File.join(root, 'test/modern_source/0080_bare_return.dabmtest')
      )
      File.binwrite(
        source_path,
        fixture.source + <<~DAB
          def custom()
          print("custom-before\\n")
          return
          print("custom-after\\n")
          end
        DAB
      )
      upper = assemble(directory, compile(source_path, lower), 'runtime')

      {
        'main' => "helper-before\nmain-after-helper\n",
        'helper' => "helper-before\n",
        'custom' => "custom-before\n",
      }.each do |entry, expected|
        output_path = File.join(directory, "#{entry}.stdout")
        stdout, stderr, status = invoke(
          vm,
          "--entry=#{entry}",
          "--out=#{output_path}",
          lower,
          upper
        )
        expect([status.exitstatus, stdout, File.binread(output_path)]).to eq([0, '', expected])
        expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
      end
    end
  end

  it 'locks the three sequential fixture contracts and exact failure streams' do
    success = DabModernSourceFixture.load(File.join(root, 'test/modern_source/0080_bare_return.dabmtest'))
    reserved = DabModernSourceFixture.load(
      File.join(root, 'test/modern_source/0081_reserved_return_function_name.dabmtest')
    )
    value = DabModernSourceFixture.load(
      File.join(root, 'test/modern_source/0082_return_value_remains_unsupported.dabmtest')
    )

    expect(success.expected_status).to eq(0)
    expect(success.expected_application_stdout).to be_nil
    expect(success.source).to include('helper-before', 'main-after-helper', 'return')
    expect(success.expected_stdout.lines.grep(/RETURN RNIL/).length).to eq(3)
    expect(success.expected_stdout).not_to include('helper-after', 'main-after-return')
    expect([reserved.expected_status, reserved.expected_stdout]).to eq([2, ''])
    expect(reserved.expected_stderr).to eq(
      'compiler: 0081_reserved_return_function_name.dabm:1:4: error: ' \
      "#{DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE}\n"
    )
    expect([value.expected_status, value.expected_stdout]).to eq([2, ''])
    expect(value.expected_stderr).to eq(
      'compiler: 0082_return_value_remains_unsupported.dabm:2:6: error: ' \
      "#{DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE}\n"
    )
  end
end
