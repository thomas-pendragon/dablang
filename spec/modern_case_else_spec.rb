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

describe 'final explicit Modern case else' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:fixture_path) { File.join(root, 'test/modern_source/0109_select_with_case.dabmtest') }
  let(:fixture) { DabModernSourceFixture.load(fixture_path) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:disassembler) { File.join(root, "bin/cdisasm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(input: 'case-else.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def lower(source, unit = DabNodeUnit.new)
    parse(source).lower_into(unit)
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
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-case-else-bundler')}
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

  def compile_source(source, directory, lower_ring, basename)
    source_path = File.join(directory, "#{basename}.dabm")
    File.binwrite(source_path, source)
    assembly, stderr, status = invoke(
      RbConfig.ruby,
      compiler,
      source_path,
      "--ring-base[]=#{lower_ring}"
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
        print(label(3))
      end

      def label(value : Int32) : String
        case value
        when 1
          return "one\n"
        when 2, 3
          return "few\n"
        else
          return "many\n"
        end
      end
    DAB
  end

  it 'parses one optional final else, including an else-only case, into frozen wrappers' do
    source = <<~DAB
      def main()
      case 1
      when 1
      "selected"
      else
      "fallback"
      end
      case 2
      else
      return
      end
      end
    DAB
    statements = parse(source).declarations.fetch(0).body_items

    expect(statements.map(&:when_clauses).map(&:length)).to eq([1, 0])
    expect(statements.map(&:else_clause)).to all(be_a(DabModernBootstrapCaseElseClause))
    expect(statements.map(&:else_clause)).to all(be_frozen)
    expect(statements.map { |statement| statement.else_clause.body }).to all(be_frozen)
    expect(statements.fetch(0).else_clause.source_parts).to eq(%W[else \n])
  end

  it 'keeps case statement-only while filling only the terminal false arm' do
    with_clauses = lower(<<~DAB)
      def main(value:Int32)
      case value
      when 1
      return
      when 2, 3
      return
      else
      return
      end
      end
    DAB
    else_only = lower("def main()\ncase 1\nelse\nreturn\nend\nend\n")

    expect(with_clauses.blocks[0].all_nodes(DabNodeIf).length).to eq(2)
    expect(with_clauses.blocks[0].all_nodes(DabNodeInstanceCall).count do |call|
      call.real_identifier.to_s == '=='
    end).to eq(3)
    expect(with_clauses.blocks[0].all_nodes(DabNodeReturn).length).to eq(3)
    expect(else_only.blocks[0].all_nodes(DabNodeIf)).to be_empty
    expect(else_only.blocks[0].all_nodes(DabNodeInstanceCall)).to be_empty
    expect(else_only.blocks[0].all_nodes(DabNodeReturn).length).to eq(1)
  end

  it 'preserves contextual else declarations, parameters, locals, calls, members, suffixes, and text' do
    source = <<~'DAB'
      def else(value:Boolean):Boolean
      return value
      end
      def else?(value:Boolean):Boolean
      return value
      end
      def names(else:String):String
      else(true)
      else?(false)
      "x".else()
      return "#{else} else"
      end
      def main()
      var else = true
      else = false
      case true
      when true
      else(false)
      else?(true)
      else
      "else".else()
      end
      end
    DAB
    document = parse(source)
    names = document.declarations.fetch(2).body_items
    statement = document.declarations.fetch(3).body_items.fetch(2)

    expect(names.take(2).map { |item| item.callable_name.text }).to eq(%w[else else?])
    expect(names.fetch(2).callable_name.text).to eq('else')
    expect(names.fetch(3).value.value.splices.map(&:name)).to eq(['else'])
    expect(statement.when_clauses.fetch(0).body.map { |item| item.callable_name.text })
      .to eq(%w[else else?])
    expect(statement.else_clause.body.fetch(0).callable_name.text).to eq('else')
  end

  it 'gives nested if, unless, and case their nearest else ownership' do
    source = <<~DAB
      def main()
      case 1
      when 1
      if false
      return
      else
      unless true
      return
      else
      case 2
      else
      return
      end
      end
      end
      else
      return
      end
      end
    DAB
    outer = parse(source).declarations.fetch(0).body_items.fetch(0)
    nested_if = outer.when_clauses.fetch(0).body.fetch(0)
    nested_unless = nested_if.if_false.fetch(0)
    nested_case = nested_unless.else_body.fetch(0)

    expect([outer, nested_case].map(&:else_clause)).to all(be_a(DabModernBootstrapCaseElseClause))
    expect(nested_if.if_false).not_to be_empty
    expect(nested_unless.else_body).not_to be_empty
  end

  it 'accepts only immediate LF, semicolon, or adjacent line-comment separators' do
    source = <<~DAB
      def main()
      case 1
      else;
      end
      case 2
      else# hash
      end
      case 3
      else// slash
      end
      end
    DAB
    clauses = parse(source).declarations.fetch(0).body_items.map(&:else_clause)
    expect(clauses.map { |clause| clause.separator.kind })
      .to eq(%i[semicolon line_comment line_comment])

    ["\r", "\r\n"].each do |separator|
      expect_error(
        "def main()\ncase 1\nelse#{separator}end\nend\n",
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
    end
  end

  it 'diagnoses every invalid else tail with exact half-open spans' do
    cases = [
      ["else \n", ' '],
      ["else\t\n", "\t"],
      ["else value\n", ' '],
      ["else:\n", ':'],
      ["else+1\n", '+'],
      ["else if true\n", ' '],
    ]
    cases.each do |tail, offending|
      source = "def main()\ncase 1\n#{tail}end\nend\n"
      expect_error(
        source,
        DabModernBootstrapParser::EXPECT_CASE_ELSE_SEPARATOR_MESSAGE,
        offending,
        offset: source.index(offending, source.index('else') + 'else'.bytesize)
      )
    end
    expect_eof_error(
      "def main()\ncase 1\nelse",
      DabModernBootstrapParser::EXPECT_CASE_ELSE_SEPARATOR_MESSAGE
    )
  end

  it 'rejects duplicate else, when after else, and invalid case body tokens exactly' do
    duplicate = "def main()\ncase 1\nelse\nreturn\nelse\nreturn\nend\nend\n"
    after_else = "def main()\ncase 1\nelse\nreturn\nwhen 1\nreturn\nend\nend\n"
    invalid_body = "def main()\ncase 1\nprint(\"body\")\nend\nend\n"

    expect_error(
      duplicate,
      DabModernBootstrapParser::DUPLICATE_CASE_ELSE_MESSAGE,
      'else',
      occurrence: :last
    )
    expect_error(
      after_else,
      DabModernBootstrapParser::WHEN_AFTER_CASE_ELSE_MESSAGE,
      'when'
    )
    expect_error(
      invalid_body,
      DabModernBootstrapParser::EXPECT_CASE_CLAUSE_OR_END_MESSAGE,
      'print'
    )
  end

  it 'preserves scanner, String, numeric, and malformed-call diagnostic precedence' do
    cases = [
      [
        "def main()\ncase 1\nelse\n@\nend\nend\n",
        DabModernBootstrapParseError::GENERIC_MESSAGE,
        '@',
      ],
      [
        "def main()\ncase 1\nelse\n9223372036854775808\nend\nend\n",
        'Modern integer literal is outside supported range 0..9223372036854775807',
        '9223372036854775808',
      ],
      [
        "def main()\ncase 1\nelse\nprint(,)\nend\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
        ',',
      ],
    ]
    cases.each { |source, message, offending| expect_error(source, message, offending) }

    unterminated = "def main()\ncase 1\nelse\n\"unterminated\nend\nend\n"
    expect_error(
      unterminated,
      'invalid Modern String literal: literal LF is not allowed; use "\\n"',
      "\n",
      offset: unterminated.index("\n", unterminated.index('"unterminated'))
    )
  end

  it 'accepts established recursive nonbinding bodies and lexical transfers only under while' do
    accepted = <<~DAB
      def main(flag:Boolean)
      while flag
      case true
      else
      "literal"
      print("call") if true
      "text".length()
      if true
      unless false
      case nil
      else
      next
      end
      end
      end
      break
      end
      end
      end
    DAB
    expect { parse(accepted) }.not_to raise_error
    expect_error(
      "def main()\ncase true\nelse\nbreak\nend\nend\n",
      DabModernBootstrapParser::UNEXPECTED_BREAK_MESSAGE,
      'break'
    )
    expect_error(
      "def main()\ncase true\nelse\nnext\nend\nend\n",
      DabModernBootstrapParser::UNEXPECTED_NEXT_MESSAGE,
      'next'
    )
  end

  it 'rejects bindings and every reassignment recursively after complete parsing' do
    cases = [
      ["def main()\ncase 1\nelse\nlet value = 1\nend\nend\n", 'let', :first],
      ["def main()\ncase 1\nelse\nif true\nvar value = 1\nend\nend\nend\n", 'var', :first],
      ["def main()\nvar value = 1\ncase value\nelse\nvalue = 2\nend\nend\n", 'value', :last],
      [
        "def main()\nvar flag = true\nwhile flag\ncase flag\nelse\nflag = false\nend\nend\nend\n",
        'flag',
        :last,
      ],
    ]
    cases.each do |source, offending, occurrence|
      message = if offending == 'value' || occurrence == :last
                  DabModernBootstrapParser::CASE_CLAUSE_REASSIGNMENT_MESSAGE
                else
                  DabModernBootstrapParser::CASE_CLAUSE_BINDING_MESSAGE
                end
      expect_error(source, message, offending, occurrence: occurrence)
    end

    malformed_tail = "def main()\ncase 1\nelse\nlet value = 1\nwhen\nend\nend\n"
    expect_error(
      malformed_tail,
      DabModernBootstrapParser::WHEN_AFTER_CASE_ELSE_MESSAGE,
      'when'
    )
  end

  it 'preflights unselected and dead else calls, results, arity, interpolation, and return types' do
    failures = [
      [
        "def main()\ncase 1\nwhen 1\nreturn\nelse\nmissing()\nend\nend\n",
        'unknown Modern call target "missing"',
      ],
      [
        "def helper(value:String):String\nreturn value\nend\ndef main()\ncase 1\nelse\nhelper()\nend\nend\n",
        'incorrect Modern call arity for "helper": got 0, expected 1',
      ],
      [
        "def main(name:Int32)\ncase 1\nelse\n\"\#{name}\"\nend\nend\n",
        'cannot interpolate Modern parameter "name" of type Int32; simple interpolation requires exact String',
      ],
      [
        "def main():String\ncase 1\nelse\nreturn 2\nend\nend\n",
        'cannot return Modern value of type Fixnum from function "main" with declared return type String',
      ],
    ]
    failures.each do |source, message|
      expect { lower(source) }.to raise_error(DabModernBootstrapParseError, message)
    end
  end

  it 'parses the complete document before preflight and leaves a supplied unit unchanged' do
    malformed = <<~DAB
      def main()
      case 1
      else
      missing()
      end
      print(,)
      end
    DAB
    expect_error(
      malformed,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )

    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    document = parse("def main()\ncase 1\nelse\nmissing()\nend\nend\n")
    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'rejects Ring-independent else failures before missing Ring and publishes nothing' do
    Dir.mktmpdir('dab-modern-case-else') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      File.binwrite(source_path, "def main()\ncase 1\nelse\n\"\#{missing}\"\nend\nend\n")
      missing_ring = File.join(directory, 'missing.dabcb')
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

  it 'locks canonical fixture 0109 and preserves exact bytes of fixtures 0106 through 0108' do
    expected_hashes = {
      '0106_case_subject_once.dabmtest' =>
        'd4e8644ab322d7cfed13dad7b10369163c74d164470997d802257c50138f8e98',
      '0107_literal_when_patterns.dabmtest' =>
        '03e28737c1182c9bb070664c7fe5040d8121b5e57bb9be08908e291df5cc5abf',
      '0108_comma_when_alternatives.dabmtest' =>
        '0a27f2efff0139e1606ae51cbb736f789a31bad5f93145643ed3e09e0f301344',
    }
    directory = File.join(root, 'test/modern_source')
    expected_hashes.each do |basename, expected_hash|
      normalized = File.binread(File.join(directory, basename)).gsub("\r\n", "\n")
      expect(Digest::SHA256.hexdigest(normalized)).to eq(expected_hash)
    end

    expect([fixture.expected_status, fixture.expected_application_stdout]).to eq([0, "few\n"])
  end

  it 'is exact across forward, reversed, and repeated artifacts and selected/unmatched native runs', :native do
    skip 'native tools are built by the complete gate' unless File.exist?(vm) && File.exist?(disassembler)

    Dir.mktmpdir('dab-case-else-native') do |directory|
      lower_ring = build_stdlib(directory)
      sources = [fixture.source, reversed_fixture_source, fixture.source]
      assemblies = sources.each_with_index.map do |source, index|
        compile_source(source, directory, lower_ring, "case-else-#{index}")
      end
      artifacts = assemblies.each_with_index.map do |assembly, index|
        assemble(assembly, directory, "case-else-#{index}")
      end

      expect(assemblies.uniq).to eq([fixture.expected_stdout])
      expect(artifacts.map(&:last).uniq.length).to eq(1)
      expect([Digest::SHA256.hexdigest(fixture.expected_stdout), fixture.expected_stdout.bytesize]).to eq(
        ['da2cf916149dc5658e1d863e1783081620e24ea4df9b27d89abc8885fcd74287', 3_914]
      )
      expect([Digest::SHA256.hexdigest(artifacts.fetch(0).last), artifacts.fetch(0).last.bytesize]).to eq(
        ['8a858f221b48f85e4aa82cf3a58f975f5b1b6cd745c8cc3a7e6272b3afaeed35', 656]
      )
      expect(fixture.expected_stdout.scan('JMP_IF').length).to eq(3)
      expect(fixture.expected_stdout.scan(/INSTCALL R\d+, R\d+, S\d+, R\d+/).length).to eq(3)

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
        ['6f43729c8d5358b15eed10310d0b14905621d206b67a9f2092a373d0b08807a5', 1_571]
      )

      outputs = [fixture.source, fixture.source.sub('label(3)', 'label(9)')].each_with_index.map do |source, index|
        assembly = compile_source(source, directory, lower_ring, "case-else-native-#{index}")
        artifact_path, = assemble(assembly, directory, "case-else-native-#{index}")
        output_path = File.join(directory, "native-#{index}.stdout")
        stdout, stderr, status = invoke(
          vm,
          '--entry=main',
          "--out=#{output_path}",
          lower_ring,
          artifact_path
        )
        expect([status.exitstatus, stdout]).to eq([0, ''])
        expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
        File.binread(output_path)
      end
      expect(outputs).to eq(%W[few\n many\n])
    end
  end
end
