require 'spec_helper'

require 'digest'
require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern regular-expression literal lexing' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:source_unit) do
    DabSourceUnit.new(input: 'regex-literal.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
  let(:unsupported_message) { DabModernBootstrapParser::UNSUPPORTED_REGEX_LITERAL_MESSAGE }

  def scanner(source)
    DabModernBootstrapScanner.new(source.b, source_unit: source_unit)
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_parse_error(source, message, span)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(span)
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  def fixture_section(path, name)
    bytes = File.binread(path)
    marker = "## #{name}\n"
    start = bytes.index(marker)
    raise "missing fixture section #{name} in #{path}" unless start

    body_start = start + marker.bytesize
    body_end = bytes.index(/^## [A-Z ]+\n/, body_start) || bytes.bytesize
    bytes.byteslice(body_start, body_end - body_start)
  end

  it 'keeps hash as the sole comment marker and freezes two ordinary slash tokens' do
    source = "# opaque // bytes\n// tail".b
    stream = scanner(source)
    tokens = []
    loop do
      token = stream.next_token
      tokens << token
      break if token.kind == :eof
    end

    expect(tokens.map(&:kind)).to eq(
      %i[line_comment line_feed unsupported unsupported space identifier eof]
    )
    expect(tokens.map(&:text)).to eq(['# opaque // bytes', "\n", '/', '/', ' ', 'tail', ''])
    expect(tokens.slice(2, 2).map { |token| [token.source_span.start_offset, token.source_span.end_offset] })
      .to eq([[18, 19], [19, 20]])
    expect(tokens).to all(be_frozen)
  end

  it 'freezes raw empty and nonempty candidates with exact component metadata' do
    cases = {
      '//'.b => ''.b,
      '/body/'.b => 'body'.b,
      '/a\\/b/'.b => 'a\\/b'.b,
      '/a\\\\/'.b => 'a\\\\'.b,
      "/\#{name}/".b => "\#{name}".b,
      '/#/'.b => '#'.b,
      "/\0\xFF/".b => "\0\xFF".b,
    }

    cases.each do |source, expected_body|
      token = scanner(source).next_token(value_entry: true)
      literal = token.value

      expect([token.kind, token.text]).to eq([:regex_literal, source])
      expect(token.diagnostic_message).to be_nil
      expect(token).to be_frozen
      expect(literal).to be_a(DabModernBootstrapRegexLiteralSource)
      expect(literal).to be_frozen
      expect(literal.source_tokens).to be_frozen
      expect(literal.source_tokens).to eq([literal.opening, literal.body, literal.closing])
      expect(literal.source_tokens).to all(be_frozen)
      expect(literal.source_unit).to equal(source_unit)
      expect(literal.source_tokens.map { |part| part.source_span.source_unit }).to all(equal(source_unit))
      expect([literal.opening.text, literal.body.text, literal.closing.text])
        .to eq(['/'.b, expected_body, '/'.b])
      expect([token.source_span.start_offset, token.source_span.end_offset]).to eq([0, source.bytesize])
      expect([literal.source_span.start_offset, literal.source_span.end_offset]).to eq([0, source.bytesize])
      expect([literal.body.source_span.start_offset, literal.body.source_span.end_offset])
        .to eq([1, source.bytesize - 1])
    end
  end

  it 'leaves apparent flags as a later identifier and rejects the candidate first' do
    stream = scanner('/a/im')
    literal = stream.next_token(value_entry: true)
    flags = stream.next_token

    expect([literal.kind, literal.text]).to eq([:regex_literal, '/a/'])
    expect([flags.kind, flags.text]).to eq([:identifier, 'im'])
    expect_parse_error("def main\n/a/im\nend\n", unsupported_message, [9, 12])
  end

  it 'emits every EOF and physical-line diagnostic at its exact byte span' do
    cases = [
      ['/abc'.b, 'unterminated Modern regular-expression literal: expected closing "/" before end of file', [4, 4]],
      [
        '/abc\\'.b,
        'unterminated Modern regular-expression literal escape: expected one byte after "\\\\" before end of file',
        [4, 5],
      ],
      ["/a\n/".b, 'invalid Modern regular-expression literal: literal LF is not allowed', [2, 3]],
      ["/a\r/".b, 'invalid Modern regular-expression literal: literal CR is not allowed', [2, 3]],
      ["/a\r\n/".b, 'invalid Modern regular-expression literal: literal CRLF is not allowed', [2, 4]],
      [
        "/a\\\n/".b,
        'invalid Modern regular-expression literal escape: line continuation is not allowed',
        [2, 4],
      ],
      [
        "/a\\\r/".b,
        'invalid Modern regular-expression literal escape: line continuation is not allowed',
        [2, 4],
      ],
      [
        "/a\\\r\n/".b,
        'invalid Modern regular-expression literal escape: line continuation is not allowed',
        [2, 5],
      ],
    ]

    cases.each do |source, message, span|
      token = scanner(source).next_token(value_entry: true)
      expect([token.kind, token.diagnostic_message]).to eq([:unsupported, message])
      expect([token.source_span.start_offset, token.source_span.end_offset]).to eq(span)
      expect(token.source_span.source_unit).to equal(source_unit)
    end
  end

  it 'requests regex scanning in every existing parser-declared value-entry slot' do
    sources = [
      "def main\n//\nend\n",
      "def main\nreturn //\nend\n",
      "def main\nlet value = //\nend\n",
      "def main\nvar value = //\nend\n",
      "def main\nvar value = nil\nvalue = //\nend\n",
      "def main\nprint(//)\nend\n",
      "def main\n//.length\nend\n",
      "def main\ncase //\nend\nend\n",
    ]

    sources.each do |source|
      offset = source.index('//')
      expect_parse_error(source, unsupported_message, [offset, offset + 2])
    end
  end

  it 'does not enable regex scanning in declarations, separators, transfer tails, conditions, or patterns' do
    cases = [
      ["//\n", DabModernBootstrapParseError::GENERIC_MESSAGE, [0, 1]],
      ["def //\nend\n", DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE, [4, 5]],
      ["def main//\nend\n", DabModernBootstrapParseError::GENERIC_MESSAGE, [8, 9]],
      ["def main\nreturn//\nend\n", DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE, [15, 16]],
      [
        "def main\nwhile true\nbreak//\nend\nend\n",
        DabModernBootstrapParser::EXPECT_BREAK_SEPARATOR_MESSAGE,
        [25, 26],
      ],
      [
        "def main\nwhile true\nnext//\nend\nend\n",
        DabModernBootstrapParser::EXPECT_NEXT_SEPARATOR_MESSAGE,
        [24, 25],
      ],
      ["def main\nif //\nend\nend\n", DabModernBootstrapParser::EXPECT_IF_CONDITION_MESSAGE, [12, 14]],
      [
        "def main\nnil if //\nend\n",
        DabModernBootstrapParser::EXPECT_POSTFIX_IF_CONDITION_MESSAGE,
        [16, 18],
      ],
      [
        "def main\ncase true\nwhen /a/\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_PATTERN_MESSAGE,
        [24, 27],
      ],
      ["def main\nnil//\nend\n", DabModernBootstrapParseError::GENERIC_MESSAGE, [12, 13]],
    ]

    cases.each do |source, message, span|
      expect_parse_error(source, message, span)
    end
  end

  it 'never reinterprets an ordinary token already frozen by lookahead' do
    parser = DabModernBootstrapParser.new('//'.b, source_unit: source_unit)
    ordinary = parser.send(:peek_token)
    requested_later = parser.send(:peek_value_token)

    expect(ordinary).to equal(requested_later)
    expect([ordinary.kind, ordinary.text]).to eq([:unsupported, '/'])
    expect([ordinary.source_span.start_offset, ordinary.source_span.end_offset]).to eq([0, 1])
    expect(parser.send(:next_token)).to equal(ordinary)
    expect(parser.send(:peek_token).source_span.start_offset).to eq(1)
  end

  it 'keeps regex tokens outside literal and value kinds with no lowering surface' do
    token = scanner('//').next_token(value_entry: true)

    expect(DabModernBootstrapParser::LITERAL_KINDS).not_to include(:regex_literal)
    expect(DabModernBootstrapParser::VALUE_KINDS).not_to include(:regex_literal)
    expect(token.value).not_to respond_to(:lower)
    expect { DabModernBootstrapLiterals.lower(token) }
      .to raise_error(ArgumentError, /unsupported Modern bootstrap literal token :regex_literal/)
  end

  it 'preserves double slash inside Strings and hash comments' do
    document = parse("# // opaque\ndef main\n\"//\"# // opaque\nend\n")
    literal = document.declarations.fetch(0).body_tokens.fetch(0)

    expect([literal.kind, literal.value]).to eq([:string, '//'])
    legacy = DabCompiler.new(DabProgramStream.new("func main(){1/1;// comment\n}", true, 'legacy.dab')).program
    expect(legacy.errors).to be_empty
  end

  it 'parse-checks nested, unselected, unreachable, and post-return candidates before preflight' do
    sources = [
      "def main\nif false\n//\nend\nend\n",
      "def main\nwhile false\nif true\n//\nend\nend\nend\n",
      "def main\ncase false\nwhen true\n//\nend\nend\n",
      "def main\nreturn\n//\nend\n",
      "def main\nmissing()\n//\nend\n",
      "def main\nend\ndef main\n//\nend\n",
    ]

    sources.each do |source|
      offset = source.index('//')
      expect_parse_error(source, unsupported_message, [offset, offset + 2])
    end
  end

  it 'gives an earlier true parser error priority over a later candidate' do
    source = "def main\nprint(,)\n//\nend\n"
    offset = source.index(',')
    expect_parse_error(
      source,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      [offset, offset + 1]
    )
  end

  it 'rejects before missing Ring loading and leaves destination and filesystem state unpublished' do
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    expect { parse("def main\n//\nend\n") }.to raise_error(DabModernBootstrapParseError, unsupported_message)
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty

    Dir.mktmpdir('dab-modern-regex') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      missing_ring = File.join(directory, 'missing.dabcb')
      File.binwrite(source_path, "def main\n//\nend\n")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}",
        chdir: root
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(stderr).to include("#{source_path}:2:0: error: #{unsupported_message}\n")
      expect(stderr).not_to include('missing.dabcb')
      expect(Dir.children(directory)).to eq(['invalid.dabm'])
    end
  end

  it 'locks fixture migration, negative publication, and prior fixture hashes' do
    modern = File.join(root, 'test/modern_source')
    expect(fixture_section(File.join(modern, '0007_comment.dabmtest'), 'STDOUT')).to eq(
      fixture_section(File.join(modern, '0009_minimal_main.dabmtest'), 'STDOUT')
    )
    expect(fixture_section(File.join(modern, '0110_regex_literal_lexing.dabmtest'), 'STATUS')).to eq("2\n")
    expect(File.binread(File.join(modern, '0110_regex_literal_lexing.dabmtest'))).not_to include(
      '## STDOUT',
      '## EXPECTED APPLICATION STDOUT'
    )

    expected_hashes = {
      '0106_case_subject_once.dabmtest' =>
        'd4e8644ab322d7cfed13dad7b10369163c74d164470997d802257c50138f8e98',
      '0107_literal_when_patterns.dabmtest' =>
        '03e28737c1182c9bb070664c7fe5040d8121b5e57bb9be08908e291df5cc5abf',
      '0108_comma_when_alternatives.dabmtest' =>
        '0a27f2efff0139e1606ae51cbb736f789a31bad5f93145643ed3e09e0f301344',
      '0109_select_with_case.dabmtest' =>
        '5d6f7e67ad4cbc95d4938d98de370640467cafe0e9b6ddad06f61bd92cf067ae',
    }
    expected_hashes.each do |basename, expected|
      expect(Digest::SHA256.file(File.join(modern, basename)).hexdigest).to eq(expected)
    end
  end
end
