require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern literal dot and property calls' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'dot-property-calls.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def invoke(*command, input: nil)
    environment = {
      'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-bundler'),
    }
    Open3.capture3(environment, *command, stdin_data: input, chdir: root)
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

  def instance_stub(name)
    DabNodeFunctionStub.new(name, nil, is_static: false)
  end

  it 'scans dot as an exact immutable one-byte token after a UTF-8 String literal' do
    source = "\"é\".length\n".b
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    tokens << scanner.next_token until tokens.last&.kind == :eof

    dot = tokens.fetch(1)
    expect([dot.kind, dot.text]).to eq([:dot, '.'])
    expect([dot.source_span.start_offset, dot.source_span.end_offset]).to eq(
      [source.index('.'), source.index('.') + 1]
    )
    expect(dot.source_span.source_unit).to equal(source_unit)
    expect(dot).to be_frozen
  end

  it 'retains immutable property and explicit member items with exact source parts and lowering' do
    source = <<~DAB
      def main
      "abc".length# property separator
      "xyz".length\t(\t)
      end
    DAB
    document = parse(source)
    property, explicit = document.declarations.fetch(0).body_items

    expect([property.kind, property.property_style?]).to eq([:literal_member_call, true])
    expect([explicit.kind, explicit.property_style?]).to eq([:literal_member_call, false])
    expect([property.receiver_type_name, property.callable_name.text]).to eq(%w[String length])
    expect(property.source_tokens.map(&:text).join).to eq('"abc".length')
    expect(explicit.source_tokens.map(&:text).join).to eq("\"xyz\".length\t(\t)")
    expect([property, explicit, property.arguments, explicit.arguments, property.source_tokens]).to all(be_frozen)

    function = document.lower_into(DabNodeUnit.new)
    property_node = function.blocks[0].all_nodes(DabNodePropertyGet).fetch(0)
    explicit_node = function.blocks[0].all_nodes(DabNodeInstanceCall).fetch(0)
    expect([property_node.real_identifier, explicit_node.real_identifier]).to eq(%w[length length])
    expect([property_node.source_cstart, property_node.source_cend]).to eq(
      [property.source_span.start_offset, property.source_span.end_offset]
    )
    expect([explicit_node.source_cstart, explicit_node.source_cend]).to eq(
      [explicit.source_span.start_offset, explicit.source_span.end_offset]
    )
  end

  it 'accepts only immediate property separators and explicit-call horizontal whitespace' do
    accepted = <<~DAB
      def main
      "a".length
      "b".length;"c".length# comment
      "d".length ()
      "e".length\t( )
      end
    DAB
    calls = parse(accepted).declarations.fetch(0).body_items
    expect(calls.map(&:property_style?)).to eq([true, true, true, false, false])

    cases = {
      'space before dot' => ["def main\n\"x\" .length\nend\n", DabModernBootstrapParseError::GENERIC_MESSAGE, ' '],
      'space after dot' => ["def main\n\"x\". length\nend\n", DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE, ' '],
      'space before property separator' => ["def main\n\"x\".length \nend\n", DabModernBootstrapParser::EXPECT_MEMBER_TAIL_MESSAGE, ' '],
      'second property dot' => ["def main\n\"x\".length.other\nend\n", DabModernBootstrapParser::EXPECT_MEMBER_TAIL_MESSAGE, '.'],
      'second explicit dot' => ["def main\n\"x\".length().other\nend\n", DabModernBootstrapParser::EXPECT_MEMBER_CALL_BODY_SEPARATOR_MESSAGE, '.'],
    }

    cases.each do |description, (source, message, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expected_offset = case description
                          when 'space before dot' then source.index(' .')
                          when 'space after dot' then source.index('. ') + 1
                          when 'space before property separator' then source.index(" \n")
                          else source.index(offending, source.index('length') + 'length'.length)
                          end
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [expected_offset, expected_offset + offending.bytesize]
        ), description
      }
    end
  end

  it 'uses dedicated missing-name, member-tail, and member-call separator diagnostics' do
    cases = {
      'missing name' => [
        "def main\n\"x\".()\nend\n",
        DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE,
        '(',
      ],
      'missing name at EOF' => [
        "def main\n\"x\".",
        DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE,
        '',
      ],
      'invalid tail' => [
        "def main\n\"x\".length? !\nend\n",
        DabModernBootstrapParser::EXPECT_MEMBER_TAIL_MESSAGE,
        ' ',
      ],
      'explicit separator' => [
        "def main\n\"x\".length() end\n",
        DabModernBootstrapParser::EXPECT_MEMBER_CALL_BODY_SEPARATOR_MESSAGE,
        ' ',
      ],
    }

    cases.each do |description, (source, message, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(error.source_span.end_offset - error.source_span.start_offset).to eq(offending.bytesize), description
      }
    end
  end

  it 'rejects every whitespace, comment, and line boundary around the adjacent dot' do
    after_dot_cases = {
      'space' => ["def main\n\"x\". length\nend\n", 1],
      'tab' => ["def main\n\"x\".\tlength\nend\n", 1],
      'line comment' => ["def main\n\"x\".# comment\nend\n", '# comment'.length],
      'line feed' => ["def main\n\"x\".\nlength\nend\n", 1],
      'carriage return' => ["def main\n\"x\".\rlength\nend\n", 1],
      'CRLF' => ["def main\n\"x\".\r\nlength\nend\n", 2],
    }

    after_dot_cases.each do |description, (source, width)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE), description
        expect(error.source_span.start_offset).to eq(source.index('.') + 1), description
        expect(error.source_span.end_offset - error.source_span.start_offset).to eq(width), description
      }
    end

    before_dot_cases = {
      'space' => ["def main\n\"x\" .length\nend\n", ' '],
      'tab' => ["def main\n\"x\"\t.length\nend\n", "\t"],
      'line feed' => ["def main\n\"x\"\n.length\nend\n", '.'],
      'line comment' => ["def main\n\"x\"# comment\n.length\nend\n", '.'],
    }

    before_dot_cases.each do |description, (source, marker)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(error.source_span.start_offset).to eq(source.index(marker, source.index('"x"') + 3)), description
      }
    end
  end

  it 'reuses the R39 explicit argument-list diagnostics once an opening parenthesis is present' do
    cases = {
      'argument or close' => ["def main\n\"x\".length(,)\nend\n", DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE],
      'argument separator' => ["def main\n\"x\".length(1 2)\nend\n", DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE],
      'argument after comma' => ["def main\n\"x\".length(1,)\nend\n", DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE],
      'unterminated' => ["def main\n\"x\".length(", DabModernBootstrapParser::EXPECT_CALL_CLOSE_MESSAGE],
    }

    cases.each do |description, (source, message)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
      }
    end
  end

  it 'distinguishes approved, unknown, unsupported, suffixed, and wrong-arity members' do
    expect(parse("def main\n\"x\".length\n\"x\".length()\nend\n").lower_into(DabNodeUnit.new)).to be_a(
      DabNodeFunction
    )

    cases = {
      'unknown String member' => [
        "def main\n\"x\".missing\nend\n",
        'unknown Modern member target "String#missing"',
        'missing',
      ],
      'unsupported String member' => [
        "def main\n\"x\".upcase\nend\n",
        'unsupported Modern member target "String#upcase" in the R40 dot/property-call subset',
        'upcase',
      ],
      'token-derived Boolean receiver' => [
        "def main\ntrue.length\nend\n",
        'unknown Modern member target "Boolean#length"',
        'length',
      ],
      'lexical suffix only' => [
        "def main\n\"x\".length?\nend\n",
        'unknown Modern member target "String#length?"',
        'length?',
      ],
    }

    cases.each do |description, (source, message, member)|
      expect do
        parse(source).lower_into(DabNodeUnit.new)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [source.index(member), source.index(member) + member.length]
        ), description
      }
    end

    source = "def main\n\"x\".length(1)\nend\n"
    call_source = '"x".length(1)'
    expect do
      parse(source).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'incorrect Modern member-call arity for "String#length": got 1, expected 0'
      )
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.index(call_source), source.index(call_source) + call_source.length]
      )
    }
  end

  it 'fails closed when any loaded String definition has an instance length method' do
    unit = DabNodeUnit.new
    unit.add_class(DabNodeClassDefinition.new('String', nil, [instance_stub('upcase')]))
    unit.add_class(DabNodeClassDefinition.new('String', nil, [instance_stub('length')]))

    expect do
      parse("def main\n\"x\".length\nend\n").lower_into(unit)
    end.to raise_error(
      DabModernBootstrapParseError,
      'unsupported Modern member target "String#length" in the R40 dot/property-call subset'
    )

    static_unit = DabNodeUnit.new
    static_length = DabNodeFunctionStub.new('length', nil, is_static: true)
    static_unit.add_class(DabNodeClassDefinition.new('String', nil, [static_length]))
    expect(parse("def main\n\"x\".length\nend\n").lower_into(static_unit)).to be_a(DabNodeFunction)
  end

  it 'preflights declaration collisions and all calls before mutating a lower unit' do
    unit = DabNodeUnit.new
    unit.add_function(DabNodeFunctionStub.new('lower', nil, is_static: false))
    original_functions = unit.functions.to_a
    original_classes = unit.classes.to_a
    original_constants = unit.constants.to_a
    source = <<~DAB
      def first
      "x".length
      end
      def second
      "x".missing
      end
    DAB

    expect do
      parse(source).lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError, 'unknown Modern member target "String#missing"')
    expect(unit.functions.to_a).to eq(original_functions)
    expect(unit.classes.to_a).to eq(original_classes)
    expect(unit.constants.to_a).to eq(original_constants)

    colliding = DabNodeUnit.new
    colliding.add_function(DabNodeFunctionStub.new('main', nil, is_static: false))
    expect do
      parse("def main\n\"x\".missing\nend\n").lower_into(colliding)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      expect(error.source_span.start_offset).to eq(4)
    }
  end

  it 'preserves R39 and deferred-expression diagnostic precedence' do
    cases = {
      'R39 result chaining' => [
        "def main\nhelper().length\nend\ndef helper\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_BODY_SEPARATOR_MESSAGE,
        '.',
      ],
      'parameter receiver' => [
        "def main(value:String)\nvalue.length\nend\n",
        DabModernBootstrapParseError::GENERIC_MESSAGE,
        'value.length',
      ],
      'nested member result' => [
        "def main\nprint(\"x\".length)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE,
        '.',
      ],
      'safe-navigation near miss' => [
        "def main\n\"x\"&.length\nend\n",
        DabModernBootstrapParseError::GENERIC_MESSAGE,
        '&',
      ],
    }

    cases.each do |description, (source, message, marker)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(error.source_span.start_offset).to eq(source.index(marker, source.index("\n") + 1)), description
      }
    end
  end

  it 'reports member syntax before attempting to load a lower Ring' do
    Dir.mktmpdir('dab-modern-member-syntax-preflight') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      File.binwrite(source_path, "def main\n\"x\".()\nend\n")
      missing_ring = File.join(directory, 'missing.dabcb')

      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:2:4: error: " \
        "#{DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE}\n"
      )
      expect(File).not_to exist(missing_ring)
    end
  end

  it 'emits every R40 diagnostic with status 2, empty stdout, and exact frontend attribution' do
    Dir.mktmpdir('dab-modern-member-diagnostics') do |directory|
      lower = build_stdlib(directory)
      cases = {
        'missing-name' => [
          "def main\n\"x\".()\nend\n",
          4,
          DabModernBootstrapParser::EXPECT_DOT_CALLABLE_NAME_MESSAGE,
        ],
        'member-tail' => [
          "def main\n\"x\".length \nend\n",
          10,
          DabModernBootstrapParser::EXPECT_MEMBER_TAIL_MESSAGE,
        ],
        'member-separator' => [
          "def main\n\"x\".length() \nend\n",
          12,
          DabModernBootstrapParser::EXPECT_MEMBER_CALL_BODY_SEPARATOR_MESSAGE,
        ],
        'unknown' => [
          "def main\n\"x\".missing\nend\n",
          4,
          'unknown Modern member target "String#missing"',
        ],
        'unsupported' => [
          "def main\n\"x\".upcase\nend\n",
          4,
          'unsupported Modern member target "String#upcase" in the R40 dot/property-call subset',
        ],
        'arity' => [
          "def main\n\"x\".length(1)\nend\n",
          0,
          'incorrect Modern member-call arity for "String#length": got 1, expected 0',
        ],
      }

      cases.each do |description, (source, column, message)|
        source_path = File.join(directory, "#{description}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{lower}"
        )

        expect([status.exitstatus, stdout]).to eq([2, '']), description
        expect(tool_stderr(stderr)).to eq(
          "compiler: #{source_path}:2:#{column}: error: #{message}\n"
        ), description
      end
    end
  end

  it 'emits existing INSTCALL RNIL and executes both spellings with discarded results', :native do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-member-runtime') do |directory|
      lower = build_stdlib(directory)
      source_path = File.join(directory, 'members.dabm')
      File.binwrite(
        source_path,
        <<~DAB
          def main
          "abc".length
          "xyz".length()
          print("R40 core\\n")
          end
        DAB
      )
      assembly = compile(source_path, lower)
      expect(assembly.scan(%r{/\* length\s+\*/\s+INSTCALL RNIL,}).length).to eq(2)
      expect(assembly).not_to match(/INSTCALL R\d/)

      bytecode, assembler_stderr, assembler_status = invoke(RbConfig.ruby, assembler, input: assembly)
      expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq([0, ''])

      upper = File.join(directory, 'members.dabcb')
      application_output = File.join(directory, 'application.stdout')
      File.binwrite(upper, bytecode)
      stdout, stderr, status = invoke(
        vm,
        '--entry=main',
        "--out=#{application_output}",
        lower,
        upper
      )

      expect([status.exitstatus, stdout, File.binread(application_output)]).to eq([0, '', "R40 core\n"])
      expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
    end
  end
end
