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

describe 'Modern return integration' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:fixture_path) { File.join(root, 'test/modern_source/0086_return_integration.dabmtest') }
  let(:fixture) { DabModernSourceFixture.load(fixture_path) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:disassembler) { File.join(root, "bin/cdisasm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(input: 'return-integration.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def invoke(*command, input: nil, binmode: false)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-return-integration-bundler')}
    Open3.capture3(environment, *command, stdin_data: input, binmode: binmode, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_parse_error(source, message, offending, offset: nil)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      start = offset || source.index(offending)
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
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

  it 'locks fixture 0086 and preserves fixtures 0080 through 0085 byte-for-byte' do
    expected_hashes = {
      '0080_bare_return.dabmtest' => 'a26d5bb5c568b1224680f3e29793f4335c92d939ed4290fb94b558f18caff1ce',
      '0081_reserved_return_function_name.dabmtest' =>
        '7b9c15431d1ca1c29a9ac1acfedd51218f4f1005e72a74659b82ae89b0b77a87',
      '0082_return_local_read_before.dabmtest' =>
        '5f9bbcd78cf2c012e7b9fa176e38f5d68f0c584287d9a267dd83f5439482654f',
      '0083_value_return.dabmtest' => 'c3e83c127e8e61c02b6fa1fd1bf9dce59ed3e94935f3a4913f094cf177b5f3a2',
      '0084_return_contract_mismatch.dabmtest' =>
        '8c22b5dedcf8b9e1a3ee914762f3fa1056a13ae6ebc9fe1b6adfcf1e75ba567d',
      '0085_call_result_return_remains_unsupported.dabmtest' =>
        '6c2850b6e8d4cc1f2d1c742063e99ee4fea7f11648e193727340e5b8ccd2b3ff',
    }
    directory = File.join(root, 'test/modern_source')

    expected_hashes.each do |basename, expected_hash|
      content = File.binread(File.join(directory, basename)).gsub("\r\n", "\n")
      expect(Digest::SHA256.hexdigest(content)).to eq(expected_hash)
    end
    expect([fixture.expected_status, fixture.expected_application_stdout]).to eq(
      [0, "bare-before\nafter-bare\nvalue-before\nafter-value\nfallthrough\nafter-fallthrough\n"]
    )
    expect(Digest::SHA256.hexdigest(fixture.expected_stdout)).to eq(
      '6d4b0c67b81fdbc53495ac0bcb3b10c868f81a9bd2aeae7d572bc05721f5bf55'
    )
    expect(fixture.expected_stdout.bytesize).to eq(4722)
  end

  it 'keeps the fixture portable through established CRLF transport normalization' do
    Dir.mktmpdir('dab-return-integration-crlf') do |directory|
      transported = File.join(directory, File.basename(fixture_path))
      content = File.binread(fixture_path).gsub("\r\n", "\n")
      File.binwrite(transported, content.gsub("\n", "\r\n"))
      loaded = DabModernSourceFixture.load(transported)

      expect(loaded.source).to eq(fixture.source)
      expect(loaded.expected_application_stdout).to eq(fixture.expected_application_stdout)
      expect(loaded.expected_stdout).to eq(fixture.expected_stdout)
    end
  end

  it 'builds byte-identical assembly and artifacts and runs main, helper, and custom entries', :native do
    expect(File).to exist(vm)
    expect(File).to exist(disassembler)

    Dir.mktmpdir('dab-return-integration-build') do |directory|
      lower = build_stdlib(directory)
      assemblies = 2.times.map do |index|
        compile_source(fixture.source, directory, lower, "integration-#{index}")
      end
      compact_source = fixture.source
                              .sub("  return\n  return \"dead-value\"\n  print(\"dead-bare-tail\\n\")\n", "  return\n")
                              .sub("  return \"value\"\n  return\n  print(\"dead-value-tail\\n\")\n", "  return \"value\"\n")
                              .sub("  return 0\n  return\n  print(\"dead-main-tail\\n\")\n", "  return 0\n")
      compact_assembly = compile_source(compact_source, directory, lower, 'compact')
      artifacts = assemblies.map.with_index do |assembly, index|
        assemble(assembly, directory, "integration-#{index}")
      end

      expect(assemblies.uniq).to eq([fixture.expected_stdout])
      expect(compact_assembly).to eq(fixture.expected_stdout)
      expect(artifacts.map(&:last).uniq.length).to eq(1)
      expect(Digest::SHA256.hexdigest(artifacts.fetch(0).last)).to eq(
        '3c15ea39bd6f2595d232b61748e87519526609090f0e50d3b9f5393c11c6266b'
      )
      expect(artifacts.fetch(0).last.bytesize).to eq(853)

      disassembly, disassembly_error, disassembly_status = invoke(disassembler, artifacts.fetch(0).first)
      expect(disassembly_status.exitstatus).to eq(0)
      normalized_disassembly = disassembly.gsub("\r\n", "\n")
      normalized_disassembly_error = disassembly_error.gsub("\r\n", "\n")
      expect([Digest::SHA256.hexdigest(normalized_disassembly), normalized_disassembly.bytesize]).to eq(
        ['73da31ef052b1f832bb50161723761672fbbf3e291ffe0f9d6c4ecc7038c7ee1', 1051]
      )
      expect(
        [Digest::SHA256.hexdigest(normalized_disassembly_error), normalized_disassembly_error.bytesize]
      ).to eq(
        ['9d118d611a9af35208d02467c1eb6ac4e776e2b6116de9d02f4a6f534edeb7e4', 420]
      )
      expect(normalized_disassembly.lines.grep(/RETURN/).map(&:strip)).to eq(
        [
          '/*     4947: */ RETURN RNIL',
          '/*     4980: */ RETURN RNIL',
          '/*     5013: */ RETURN RNIL',
          '/*     5127: */ RETURN R3',
          '/*     5179: */ RETURN R1',
        ]
      )

      expected_by_entry = {
        'main' => fixture.expected_application_stdout,
        'bare_explicit' => "bare-before\n",
        'value_explicit' => "value-before\n",
        'fallthrough_explicit' => "fallthrough\n",
      }
      expected_by_entry.each do |entry, expected_output|
        output_path = File.join(directory, "#{entry}.stdout")
        stdout, stderr, status = invoke(
          vm,
          "--entry=#{entry}",
          "--out=#{output_path}",
          lower,
          artifacts.fetch(0).first
        )
        expect([status.exitstatus, stdout, File.binread(output_path)]).to eq([0, '', expected_output])
        expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
      end
    end
  end

  it 'coexists with exact Nil and register returns while eliminating every dead-tail effect' do
    assembly = fixture.expected_stdout
    expect(assembly.lines.grep(/RETURN/).map(&:strip)).to eq(
      ['RETURN RNIL', 'RETURN RNIL', 'RETURN RNIL', 'RETURN R3', 'RETURN R1']
    )
    expect(assembly).not_to include('dead-value', 'dead-bare-tail', 'dead-value-tail', 'dead-main-tail')
    expect(assembly.scan('W_STRING "value"').length).to eq(1)
    expect(assembly.lines.grep(/CALL RNIL, S/).length).to eq(3)
    expect(assembly).not_to match(/\bR4\b/)
  end

  it 'lowers bare and value returns once without inserting a return-site conversion' do
    source = <<~DAB
      def bare():String
      return
      end
      def numeric():Int32
      return 1
      end
      def member():Int32
      return "abc".length
      end
    DAB
    functions = parse(source).lower_into(DabNodeUnit.new)
    returns = functions.map { |function| function.blocks[0].all_nodes(DabNodeReturn).fetch(0) }

    expect(returns.fetch(0).value).to be_a(DabNodeLiteralNil)
    expect(returns.fetch(1).value).to be_a(DabNodeLiteralNumber)
    expect(returns.fetch(1).value.my_type.type_string).to eq('Fixnum')
    expect(returns.fetch(2).value).to be_a(DabNodeModernMemberResult)
    expect(returns.fetch(2).value.instance_variable_get(:@consumed)).to be(true)
  end

  it 'preflights complete unreachable structural and local tails before Ring I/O' do
    cases = {
      'structure' => [
        "def main()\nreturn\nprint(,)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ],
      'local' => [
        "def main()\nreturn\nlet value:String = 1\nend\n",
        'cannot initialize Modern local "value" of type String with literal of type Fixnum',
      ],
    }

    Dir.mktmpdir('dab-return-integration-preflight') do |directory|
      missing_ring = File.join(directory, 'missing.dabcb')
      cases.each do |name, (source, message)|
        source_path = File.join(directory, "#{name}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{missing_ring}"
        )

        expect([status.exitstatus, stdout]).to eq([2, ''])
        expect(tool_stderr(stderr)).to include("error: #{message}")
        expect(File).not_to exist(missing_ring)
      end
    end
  end

  it 'preflights unreachable calls and members before publishing any partial unit' do
    cases = {
      'call' => [
        "def main()\nreturn\nmissing()\nend\n",
        'unknown Modern call target "missing"',
        'missing',
      ],
      'member' => [
        "def main()\nreturn\n\"x\".missing\nend\n",
        'unknown Modern member target "String#missing"',
        'missing',
      ],
    }

    cases.each_value do |source, message, offending|
      document = parse(source)
      unit = DabNodeUnit.new
      existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
      unit.add_function(existing)

      expect { document.lower_into(unit) }.to raise_error(DabModernBootstrapParseError) { |error|
        start = source.index(offending)
        expect(error.message).to eq(message)
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [start, start + offending.bytesize]
        )
      }
      expect(unit.functions.to_a).to eq([existing])
      expect(unit.constants.to_a).to be_empty
    end

    Dir.mktmpdir('dab-return-integration-ring-preflight') do |directory|
      lower = build_stdlib(directory)
      cases.each do |name, (source, message, _offending)|
        source_path = File.join(directory, "#{name}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{lower}"
        )

        expect([status.exitstatus, stdout]).to eq([2, ''])
        expect(tool_stderr(stderr)).to include("error: #{message}")
      end
      expect(Dir.children(directory).sort).to eq(%w[call.dabm member.dabm stdlib.dabca stdlib.dabcb])
    end
  end

  it 'keeps global reservation, exact separators, malformed return(), and spans unchanged' do
    scanner = DabModernBootstrapScanner.new(
      'return Return returns return1 _return'.b,
      source_unit: source_unit
    )
    tokens = []
    tokens << scanner.next_token until tokens.last&.kind == :eof
    words = tokens.reject { |token| %i[space eof].include?(token.kind) }
    expect(words.map { |token| [token.kind, token.text] }).to eq(
      [
        [:return, 'return'],
        [:identifier, 'Return'],
        [:identifier, 'returns'],
        [:identifier, 'return1'],
        [:identifier, '_return'],
      ]
    )

    bare_message = DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE
    value_message = DabModernBootstrapParser::EXPECT_VALUE_RETURN_SEPARATOR_MESSAGE
    direct_call = "def main()\nreturn()\nend\n"
    expect_parse_error(direct_call, bare_message, '(', offset: direct_call.index('return') + 6)
    tab = "def main()\nreturn\t1\nend\n"
    expect_parse_error(tab, bare_message, "\t")
    double_space = "def main()\nreturn  1\nend\n"
    expect_parse_error(double_space, bare_message, ' ', offset: double_space.index('return') + 6)
    operator = "def main()\nreturn 1+2\nend\n"
    expect_parse_error(operator, value_message, '+')
  end

  it 'keeps parameters, call results, member-on-local, and general expressions rejected' do
    cases = {
      'parameter' => ["def value(arg:String):String\nreturn arg\nend\n", 'arg'],
      'call result' => [
        "def helper():String\nreturn \"x\"\nend\ndef main():String\nreturn helper()\nend\n",
        'helper',
      ],
      'member on local' => [
        "def main():Int32\nlet value = \"x\"\nreturn value.length\nend\n",
        'value',
      ],
    }
    cases.each_value do |source, offending|
      expect_parse_error(
        source,
        DabModernBootstrapParseError::GENERIC_MESSAGE,
        offending,
        offset: source.index(offending, source.index('return') + 6)
      )
    end

    parenthesized = "def main():Fixnum\nreturn (1)\nend\n"
    expect_parse_error(
      parenthesized,
      DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE,
      ' ',
      offset: parenthesized.index('return') + 6
    )
  end

  it 'contains String-literal length to exact Int32 or omitted Object contracts' do
    expect { parse("def exact():Int32\nreturn \"abc\".length\nend\n") }.not_to raise_error
    expect { parse("def omitted()\nreturn \"abc\".length()\nend\n") }.not_to raise_error

    mismatch = "def mismatch():Fixnum\nreturn \"abc\".length\nend\n"
    expect do
      parse(mismatch).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expression = '"abc".length'
      start = mismatch.index(expression)
      expect(error.message).to eq(
        'cannot return Modern value of type Int32 from function "mismatch" with declared return type Fixnum'
      )
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + expression.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end
end
