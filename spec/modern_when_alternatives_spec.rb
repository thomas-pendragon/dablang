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

describe 'lazy comma-separated Modern when alternatives' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:fixture_path) { File.join(root, 'test/modern_source/0108_comma_when_alternatives.dabmtest') }
  let(:fixture) { DabModernSourceFixture.load(fixture_path) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:disassembler) { File.join(root, "bin/cdisasm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(input: 'when-alternatives.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_error(source, message, offending, occurrence: :first, offset: nil, lower_document: false)
    action = proc do
      document = parse(source)
      document.lower_into(DabNodeUnit.new) if lower_document
    end
    expect(&action).to raise_error(DabModernBootstrapParseError) { |error|
      start = offset || (occurrence == :last ? source.rindex(offending) : source.index(offending))
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  def expect_eof_error(source, message)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.bytesize, source.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  def invoke(*command, input: nil, binmode: false)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-when-alternatives-bundler')}
    Open3.capture3(environment, *command, stdin_data: input, binmode: binmode, chdir: root)
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
    expect(tool_stderr(stderr)).not_to match(/error|failed|exception/i)
    artifact
  end

  def compile_source(source, directory, lower, basename)
    source_path = File.join(directory, "#{basename}.dabm")
    File.binwrite(source_path, source)
    assembly, stderr, status = invoke(
      RbConfig.ruby,
      compiler,
      source_path,
      "--ring-base[]=#{lower}"
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    assembly
  end

  def assemble(assembly, directory, basename)
    artifact, stderr, status = invoke(
      RbConfig.ruby,
      '-e',
      'STDOUT.binmode; load ARGV.shift',
      assembler,
      input: assembly,
      binmode: true
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    path = File.join(directory, "#{basename}.dabcb")
    File.binwrite(path, artifact)
    [path, artifact]
  end

  def reversed_fixture_source
    <<~'DAB'
      def main()
      case subject()
      when 1, 2, 2, "2"
      print("matched-two-alternative\n")
      when 2
      print("wrong-later-clause\n")
      end
      print("after-first\n")
      case second_subject()
      when 1, 2
      print("wrong-first-clause\n")
      when 3, 4
      print("matched-second-clause\n")
      end
      print("after-second\n")
      case 2
      when "2", 2
      print("matched-after-mismatch\n")
      end
      case empty_subject()
      when false, true
      when true
      print("wrong-empty-fallthrough\n")
      end
      print("after-empty\n")
      let label = "2"
      case label
      when "x", "#{label}", "later"
      print("matched-interpolation\n")
      when "2"
      print("wrong-interpolation-fallthrough\n")
      end
      print("after-interpolation\n")
      end
      def empty_subject():Boolean
      print("empty-subject\n")
      return true
      end
      def second_subject():Fixnum
      print("second-subject\n")
      return 3
      end
      def subject():Fixnum
      print("subject\n")
      return 2
      end
    DAB
  end

  it 'parses one or more ordered existing literals with optional SPACE and TAB around commas' do
    source = <<~'DAB'
      def main(name:String)
      case name
      when nil,true , false,	9223372036854775807 ,	"static",	 "#{name}"
      end
      end
    DAB
    clause = parse(source).declarations.fetch(0).body_items.fetch(0).when_clauses.fetch(0)

    expect(clause.patterns.map(&:kind)).to eq(
      %i[nil boolean_true boolean_false integer string interpolated_string]
    )
    expect(clause.pattern).to equal(clause.patterns.fetch(0))
    expect(clause.patterns).to be_frozen
    expect(clause.pattern_tokens).to be_frozen
    expect(clause.source_parts.join).to eq(
      "when nil,true , false,\t9223372036854775807 ,\t\"static\",\t \"\#{name}\"\n"
    )
    expect(clause).to be_frozen
  end

  it 'preserves the exact single-pattern wrapper and lowering shape' do
    clause = parse("def main()\ncase true\nwhen true\nend\nend\n")
             .declarations.fetch(0).body_items.fetch(0).when_clauses.fetch(0)
    statement = parse("def main()\ncase true\nwhen true\nend\nend\n")
                .declarations.fetch(0).body_items.fetch(0)
    lowered = statement.lower

    expect(clause.patterns).to eq([clause.pattern])
    expect(lowered.all_nodes(DabNodeOperator)).to be_empty
    expect(lowered.all_nodes(DabNodeIf).length).to eq(1)
    expect(lowered.all_nodes(DabNodeInstanceCall).count { |call| call.real_identifier.to_s == '==' })
      .to eq(1)
  end

  it 'lowers alternatives into marked left-to-right equality, internal OR, and one shared body per clause' do
    source = <<~DAB
      def main()
      case 2
      when "2", 2, 2
      "selected-once"
      when 3, 4
      "later-once"
      end
      end
    DAB
    statement = parse(source).declarations.fetch(0).body_items.fetch(0)
    lowered = statement.lower
    comparisons = lowered.all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == '=='
    end
    operators = lowered.all_nodes(DabNodeOperator)
    selected = lowered.all_nodes(DabNodeLiteralString).count do |literal|
      literal.constant_value == 'selected-once'
    end

    expect(comparisons.length).to eq(5)
    expect(comparisons).to all(be_compiler_verified_target)
    expect(comparisons.map { |call| call.args.fetch(0).real_identifier.to_s }.uniq.length).to eq(1)
    expect(operators.map { |operator| operator.identifier.extra_value }).to eq(%w[|| || ||])
    expect(lowered.all_nodes(DabNodeIf).length).to eq(2)
    expect(selected).to eq(1)
  end

  it 'constructs clauses and alternatives linearly without suffix-array copies' do
    parsed = parse(<<~DAB).declarations.fetch(0).body_items.fetch(0)
      def main()
      case true
      when 1, 2, 3, 4
      end
      end
    DAB
    no_suffix_patterns = Class.new(Array) do
      def drop(*)
        raise 'alternative suffix arrays must not be copied'
      end

      def reverse
        raise 'alternative arrays must not be reversed by copying'
      end
    end.new(parsed.when_clauses.fetch(0).patterns)
    clause = DabModernBootstrapWhenClause.new(
      when_token: parsed.when_clauses.fetch(0).when_token,
      space_token: parsed.when_clauses.fetch(0).space_token,
      patterns: no_suffix_patterns,
      pattern_tokens: parsed.when_clauses.fetch(0).pattern_tokens,
      pattern_separator: parsed.when_clauses.fetch(0).pattern_separator,
      body: parsed.when_clauses.fetch(0).body,
      end_location: parsed.when_clauses.fetch(0).source_span.end_location
    )
    statement = DabModernBootstrapCaseStatement.new(
      case_token: parsed.case_token,
      space_token: parsed.space_token,
      subject: parsed.subject,
      subject_separator: parsed.subject_separator,
      when_clauses: [clause],
      end_token: parsed.end_token,
      final_separator: parsed.final_separator
    )

    expect(statement.lower.all_nodes(DabNodeOperator).length).to eq(3)
  end

  it 'retains contextual calls, recursive nonbinding bodies, and nearest transfer ownership' do
    source = <<~DAB
      def when(value:Boolean):Boolean
      return value
      end
      def when?(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean)
      while flag
      case 1
      when 0, 1
      when(false)
      when?(true)
      if true
      case 2
      when 2, 3
      next
      end
      end
      break
      end
      end
      end
    DAB
    document = parse(source)
    body = document.declarations.fetch(2).body_items.fetch(0).loop_items.fetch(0)
                   .when_clauses.fetch(0).body

    expect(body.take(2).map { |item| item.callable_name.text }).to eq(%w[when when?])
    expect { document.lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'locks missing, trailing, doubled, comment, semicolon, and EOF alternative spans' do
    message = DabModernBootstrapParser::EXPECT_WHEN_ALTERNATIVE_MESSAGE
    trailing = "def main()\ncase 1\nwhen 1,\nend\nend\n"
    expect_error(
      trailing,
      message,
      "\n",
      offset: trailing.index("\n", trailing.index('when 1,'))
    )
    cases = [
      ["def main()\ncase 1\nwhen 1,,2\nend\nend\n", ',', :last],
      ["def main()\ncase 1\nwhen 1,# comment\nend\nend\n", '# comment', :first],
      ["def main()\ncase 1\nwhen 1,;\nend\nend\n", ';', :first],
    ]
    cases.each do |source, offending, occurrence|
      expect_error(source, message, offending, occurrence: occurrence)
    end
    expect_eof_error("def main()\ncase 1\nwhen 1,", message)
    expect_error(
      "def main()\ncase 1\nwhen ,\nend\nend\n",
      DabModernBootstrapParser::EXPECT_WHEN_PATTERN_MESSAGE,
      ','
    )
  end

  it 'owns rejected forms after a comma while preserving malformed-form diagnostic precedence' do
    message = DabModernBootstrapParser::EXPECT_WHEN_ALTERNATIVE_MESSAGE
    cases = [
      ["def main()\ncase 1\nwhen 1,value + 2\nend\nend\n", message, 'value + 2'],
      ["def main()\ncase 1\nwhen 1,helper()\nend\nend\n", message, 'helper()'],
      ["def main()\ncase 1\nwhen 1,\"x\".length\nend\nend\n", message, '"x".length'],
      [
        "def main()\ncase 1\nwhen 1,helper(,)\nend\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
        ',',
        :last,
      ],
      [
        "def main()\ncase 1\nwhen 1,9223372036854775808\nend\nend\n",
        'Modern integer literal is outside supported range 0..9223372036854775807',
        '9223372036854775808',
      ],
      [
        "def main()\ncase 1\nwhen 1,1.0\nend\nend\n",
        'invalid Modern numeric literal: decimal fractions are not implemented',
        '.',
      ],
    ]
    cases.each do |source, expectation, offending, occurrence|
      expect_error(source, expectation, offending, occurrence: occurrence || :first)
    end

    unterminated = "def main()\ncase 1\nwhen 1,\"unterminated\nend\nend\n"
    expect_error(
      unterminated,
      'invalid Modern String literal: literal LF is not allowed; use "\\n"',
      "\n",
      offset: unterminated.index("\n", unterminated.index('"unterminated'))
    )
  end

  it 'preserves final-separator, operator, whitespace, CR, and CRLF diagnostics' do
    separator_message = DabModernBootstrapParser::EXPECT_WHEN_PATTERN_SEPARATOR_MESSAGE
    expect_error("def main()\ncase 1\nwhen 1+2\nend\nend\n", separator_message, '+')
    expect_error(
      "def main()\ncase 1\nwhen 1 \nend\nend\n",
      separator_message,
      ' ',
      occurrence: :last
    )
    ["\r", "\r\n"].each do |separator|
      expect_error(
        "def main()\ncase 1\nwhen 1,#{separator}end\nend\n",
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
    end
  end

  it 'parses the complete document before preflight and preflights dead alternatives' do
    malformed_later = <<~'DAB'
      def main(name:String)
      case true
      when true, "#{missing}"
      end
      print(,)
      end
    DAB
    expect_error(
      malformed_later,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ',',
      occurrence: :last
    )

    dead = <<~'DAB'
      def main()
      return
      case true
      when true, "#{missing}"
      end
      end
    DAB
    expect_error(
      dead,
      'unknown Modern interpolation local "missing"; expected an earlier same-function local binding',
      'missing'
    )
  end

  it 'keeps the destination unit and filesystem unpublished on Ring-independent failure' do
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    document = parse(<<~DAB)
      def main()
      case true
      when false, true
      missing()
      end
      end
    DAB

    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty

    Dir.mktmpdir('dab-when-alternative-publication') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      missing_ring = File.join(directory, 'missing.dabcb')
      File.binwrite(source_path, <<~'DAB')
        def main()
        case true
        when true, "#{missing}"
        end
        end
      DAB
      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to include('unknown Modern interpolation local "missing"')
      expect(Dir.children(directory)).to eq(['invalid.dabm'])
    end
  end

  it 'locks fixture 0108 and preserves the complete bytes of fixtures 0106 and 0107' do
    expected_hashes = {
      '0106_case_subject_once.dabmtest' =>
        'd4e8644ab322d7cfed13dad7b10369163c74d164470997d802257c50138f8e98',
      '0107_literal_when_patterns.dabmtest' =>
        '03e28737c1182c9bb070664c7fe5040d8121b5e57bb9be08908e291df5cc5abf',
    }
    directory = File.join(root, 'test/modern_source')
    expected_hashes.each do |basename, expected_hash|
      normalized = File.binread(File.join(directory, basename)).gsub("\r\n", "\n")
      expect(Digest::SHA256.hexdigest(normalized)).to eq(expected_hash)
    end

    expect([fixture.expected_status, fixture.expected_application_stdout]).to eq(
      [
        0,
        "subject\nmatched-two-alternative\nafter-first\nsecond-subject\n" \
        "matched-second-clause\nafter-second\nmatched-after-mismatch\n" \
        "empty-subject\nafter-empty\nmatched-interpolation\nafter-interpolation\n",
      ]
    )
    expect([Digest::SHA256.hexdigest(fixture.expected_stdout), fixture.expected_stdout.bytesize]).to eq(
      ['18d1163f474f42ca152f514762a230bff976ceac44757958a4ef0c82da70ca5e', 11_230]
    )
  end

  it 'is exact across forward, reversed, and repeated assembly, artifact, disassembly, and native runs', :native do
    skip 'native tools are built by the complete gate' unless File.exist?(vm) && File.exist?(disassembler)

    Dir.mktmpdir('dab-when-alternative-native') do |directory|
      lower = build_stdlib(directory)
      sources = [fixture.source, reversed_fixture_source, fixture.source]
      assemblies = sources.each_with_index.map do |source, index|
        compile_source(source, directory, lower, "alternatives-#{index}")
      end
      artifacts = assemblies.each_with_index.map do |assembly, index|
        assemble(assembly, directory, "alternatives-#{index}")
      end

      expect(assemblies.uniq).to eq([fixture.expected_stdout])
      expect(artifacts.map(&:last).uniq.length).to eq(1)
      expect([Digest::SHA256.hexdigest(artifacts.fetch(0).last), artifacts.fetch(0).last.bytesize]).to eq(
        ['4b5f1cd069d9d1e963c63107bf9a2ff4b70c2c35136c2cae954642534c11dc85', 1_893]
      )
      expect(fixture.expected_stdout.scan(/INSTCALL R\d+, R\d+, S\d+, R\d+/).length).to eq(18)
      expect(fixture.expected_stdout.scan('JMP_IF').length).to eq(18)

      disassemblies = 2.times.map do
        stdout, stderr, status = invoke(
          disassembler,
          '--with-headers',
          '--no-numbers',
          artifacts.fetch(0).first
        )
        expect(status.exitstatus).to eq(0)
        expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
        stdout.gsub("\r\n", "\n")
      end
      expect(disassemblies.uniq.length).to eq(1)
      expect([Digest::SHA256.hexdigest(disassemblies.fetch(0)), disassemblies.fetch(0).bytesize]).to eq(
        ['21f4b824d5fd7eb0df22b96d32e35614dd5641211d96f5f7470b7dc78bb3e399', 8_035]
      )

      outputs = 2.times.map do |index|
        output_path = File.join(directory, "native-#{index}.stdout")
        stdout, stderr, status = invoke(
          vm,
          '--entry=main',
          "--out=#{output_path}",
          lower,
          artifacts.fetch(0).first
        )
        expect([status.exitstatus, stdout]).to eq([0, ''])
        expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
        File.binread(output_path)
      end
      expect(outputs).to eq([fixture.expected_application_stdout, fixture.expected_application_stdout])
      expect(Digest::SHA256.hexdigest(outputs.fetch(0))).to eq(
        'cf5023fa8d27a13b49fb3ae5f3803d5b0019a3b232d633fdac5d3af8ed87f81f'
      )
    end
  end
end
