require 'spec_helper'

require 'digest'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern regular-expression literal lexing' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:source_unit) do
    DabSourceUnit.new(input: 'regex-literal.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
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

  def expect_lower_error(source, message, span)
    expect { parse(source).lower_into(DabNodeUnit.new) }
      .to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message)
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(span)
        expect(error.source_span.source_unit).to equal(source_unit)
      }
  end

  def fixture_section(path, name)
    bytes = File.binread(path).gsub("\r\n", "\n")
    marker = "## #{name}\n"
    start = bytes.index(marker)
    raise "missing fixture section #{name} in #{path}" unless start

    body_start = start + marker.bytesize
    body_end = bytes.index(/^## [A-Z ]+\n/, body_start) || bytes.bytesize
    bytes.byteslice(body_start, body_end - body_start)
  end

  def normalized_fixture_sha256(path)
    Digest::SHA256.hexdigest(File.binread(path).gsub("\r\n", "\n"))
  end

  it 'normalizes CRLF fixture transport before locating sections' do
    Dir.mktmpdir('dab-modern-regex-crlf') do |directory|
      path = File.join(directory, 'fixture.dabmtest')
      File.binwrite(
        path,
        "## SOURCE\r\ndef main\r\nend\r\n## STDOUT\r\nassembly\r\n## STATUS\r\n0\r\n"
      )

      expect(fixture_section(path, 'STDOUT')).to eq("assembly\n")
    end
  end

  it 'normalizes CRLF fixture transport before hashing canonical bytes' do
    canonical_path = File.join(root, 'test/modern_source/0106_case_subject_once.dabmtest')
    canonical = File.binread(canonical_path).gsub("\r\n", "\n")

    Dir.mktmpdir('dab-modern-regex-crlf-hash') do |directory|
      path = File.join(directory, 'fixture.dabmtest')
      File.binwrite(path, canonical.gsub("\n", "\r\n"))

      expect(normalized_fixture_sha256(path)).to eq(Digest::SHA256.hexdigest(canonical))
    end
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

  it 'leaves apparent flags as a later identifier for the enclosing grammar to reject' do
    stream = scanner('/a/im')
    literal = stream.next_token(value_entry: true)
    flags = stream.next_token

    expect([literal.kind, literal.text]).to eq([:regex_literal, '/a/'])
    expect([flags.kind, flags.text]).to eq([:identifier, 'im'])
    expect_parse_error("def main\n/a/im\nend\n", DabModernBootstrapParseError::GENERIC_MESSAGE, [12, 14])
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

  it 'admits Regex values in exactly the eight parser-declared value-entry forms' do
    sources = [
      "def main\n// if false\nend\n",
      "def main\nreturn //\nend\n",
      "def main\nlet value = //\nend\n",
      "def main\nvar value = //\nend\n",
      "def main\nvar value = //\nvalue = /a/\nend\n",
      "def main\nprint(//)\nend\n",
      "def main\nprint(print(//))\nend\n",
      "def main\n//.class\nend\n",
      "def main\ncase //\nend\nend\n",
    ]

    sources.each do |source|
      expect { parse(source) }.not_to raise_error
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
      [
        "def main\ncase true\nwhen true, /a/\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_ALTERNATIVE_MESSAGE,
        [30, 33],
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

  it 'keeps Regex contextual while lowering raw bodies through the existing constructor shape' do
    token = scanner("/a\0\xFF/".b).next_token(value_entry: true)
    lowered = DabModernBootstrapLiterals.lower(token)
    pattern = lowered.args.fetch(0)
    output = StringIO.new

    expect(DabModernBootstrapParser::LITERAL_KINDS).not_to include(:regex_literal)
    expect(DabModernBootstrapParser::VALUE_KINDS).not_to include(:regex_literal)
    expect(token.value).not_to respond_to(:lower)
    expect(lowered).to be_a(DabNodeInstanceCall)
    expect([lowered.value.class, lowered.value.identifier, lowered.real_identifier])
      .to eq([DabNodeClass, 'Regex', 'new'])
    expect([pattern.class, pattern.string]).to eq([DabNodeLiteralString, "a\0\xFF".b])
    expect(DabModernBootstrapLiterals.flow_type(token)).to be_a(DabTypeRegex)
    expect(DabModernBootstrapLiterals.type(token)).to be_a(DabTypeRegex)

    pattern.compile_string(DabOutput.new(double(stdout: output)))
    expect(output.string).not_to include('W_STRING')
    expect(output.string.scan('W_BYTE').length).to eq(pattern.string.bytesize + 1)
    ordinary = DabNodeLiteralString.new(pattern.string, modern_source: true)
    expect(pattern.constant_table_key).not_to eq(ordinary.constant_table_key)

    source_spans = lowered.source_parts.map { |part| [part.source_cstart, part.source_cend] }
    expect(source_spans).to include([0, 1], [1, 4], [4, 5])
    expect(pattern.source_parts.map { |part| [part.source_cstart, part.source_cend] }).to include([1, 4])
  end

  it 'maps every pattern-relative byte offset to a zero-width raw source point' do
    literal = scanner('/a\\/b/'.b).next_token(value_entry: true).value

    (0..literal.body.text.bytesize).each do |offset|
      point = literal.source_span_for_pattern_offset(offset)
      absolute = literal.body.source_span.start_offset + offset
      expect([point.start_offset, point.end_offset]).to eq([absolute, absolute])
      expect(point.source_unit).to equal(source_unit)
      expect(point.start_location.line).to eq(literal.body.source_span.start_location.line)
      expect(point.start_location.column).to eq(literal.body.source_span.start_location.column + offset)
    end
    expect { literal.source_span_for_pattern_offset(-1) }
      .to raise_error(DabSourceLocationError, 'Regex pattern byte offset is outside literal body')
    expect { literal.source_span_for_pattern_offset(literal.body.text.bytesize + 1) }
      .to raise_error(DabSourceLocationError, 'Regex pattern byte offset is outside literal body')
  end

  it 'preserves double slash inside Strings and hash comments' do
    document = parse("# // opaque\ndef main\n\"//\"# // opaque\nend\n")
    literal = document.declarations.fetch(0).body_tokens.fetch(0)

    expect([literal.kind, literal.value]).to eq([:string, '//'])
    legacy = DabCompiler.new(DabProgramStream.new("func main(){1/1;// comment\n}", true, 'legacy.dab')).program
    expect(legacy.errors).to be_empty
  end

  it 'parse-checks nested, unselected, unreachable, and post-return Regex values' do
    sources = [
      "def main\nif false\n//\nend\nend\n",
      "def main\nwhile false\nif true\n//\nend\nend\nend\n",
      "def main\ncase false\nwhen true\n//\nend\nend\n",
      "def main\nreturn\n//\nend\n",
      "def main\nmissing()\n//\nend\n",
      "def main\nend\ndef main\n//\nend\n",
    ]

    sources.each do |source|
      expect { parse(source) }.not_to raise_error
    end

    malformed = "def main\nif false\n/unterminated\nend\nend\n"
    offset = malformed.index("\n", malformed.index('/'))
    expect_parse_error(
      malformed,
      'invalid Modern regular-expression literal: literal LF is not allowed',
      [offset, offset + 1]
    )
  end

  it 'keeps the while guard Boolean-only and preserves Regex member exclusions' do
    while_source = "def main\nvar guard = true\nwhile guard\nguard = /a/\nend\nend\n"
    offset = while_source.index('/a/')
    expect_parse_error(
      while_source,
      DabModernBootstrapParser::EXPECT_WHILE_GUARD_REASSIGNMENT_VALUE_MESSAGE,
      [offset, offset + 3]
    )

    class_source = "def main\n/a/.class\nend\n"
    expect_lower_error(
      class_source,
      'unsupported Modern member target "Regex#class" in the R40 dot/property-call subset',
      [class_source.index('class'), class_source.index('class') + 5]
    )
    match_source = "def main\n/a/.matches?(\"x\")\nend\n"
    expect_lower_error(
      match_source,
      'unknown Modern member target "Regex#matches?"',
      [match_source.index('matches?'), match_source.index('matches?') + 8]
    )
  end

  it 'uses the internal Regex flow type without admitting written Regex annotations' do
    cases = [
      [
        "def main\nlet value : String = /a/\nend\n",
        'cannot initialize Modern local "value" of type String with literal of type Regex',
      ],
      [
        "def main : String\nreturn /a/\nend\n",
        'cannot return Modern value of type Regex from function "main" with declared return type String',
      ],
      [
        "def take(value : String)\nend\ndef main\ntake(/a/)\nend\n",
        'cannot pass Modern argument of type Regex to parameter "value" of type String in call "take"',
      ],
    ]
    cases.each do |source, message|
      offset = source.index('/a/')
      expect_lower_error(source, message, [offset, offset + 3])
    end

    annotation = "def main(value : Regex)\nend\n"
    offset = annotation.index('Regex')
    supported = DabModernBootstrapParser::SUPPORTED_TYPE_NAMES
    expect_parse_error(
      annotation,
      %(unknown Modern type "Regex"; supported types are ) \
      "#{supported[0...-1].join(', ')}, and #{supported.fetch(-1)}",
      [offset, offset + 5]
    )
    expect(DabModernBootstrapParser::SUPPORTED_TYPE_NAMES).not_to include('Regex')
  end

  it 'keeps Regex out of general Legacy type parsing and annotation sites' do
    expect { DabType.parse('Regex') }.to raise_error(RuntimeError, 'Unknown type Regex')

    annotations = [
      'func main<Regex>() {}',
      'func main(value<Regex>) {}',
      'func main() { var<Regex> value; }',
    ]
    annotations.each do |source|
      stream = DabProgramStream.new(source, true, 'legacy-regex-annotation.dab')
      expect { DabCompiler.new(stream).program }.to raise_error(RuntimeError, 'Unknown type Regex')
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

  it 'keeps compiler failures transactional and ahead of missing Ring loading' do
    source = "def main\nlet value : String = //\nend\n"
    diagnostic = 'cannot initialize Modern local "value" of type String with literal of type Regex'
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError, diagnostic)
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty

    Dir.mktmpdir('dab-modern-regex') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      missing_ring = File.join(directory, 'missing.dabcb')
      File.binwrite(source_path, source)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}",
        chdir: root
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(stderr).to include("#{source_path}:2:21: error: #{diagnostic}\n")
      expect(stderr).not_to include('missing.dabcb')
      expect(Dir.children(directory)).to eq(['invalid.dabm'])
    end
  end

  it 'locks positive fixture admission and prior fixture hashes' do
    modern = File.join(root, 'test/modern_source')
    expect(fixture_section(File.join(modern, '0007_comment.dabmtest'), 'STDOUT')).to eq(
      fixture_section(File.join(modern, '0009_minimal_main.dabmtest'), 'STDOUT')
    )
    fixture = File.join(modern, '0110_regex_literal_lexing.dabmtest')
    expect(fixture_section(fixture, 'STATUS')).to eq("0\n")
    expect(fixture_section(fixture, 'EXPECTED APPLICATION STDOUT')).to eq("regex literals\n\n")
    expect(fixture_section(fixture, 'STDOUT')).to include('LOAD_CLASS', ' 20', 'INSTCALL', 'new')

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
      expect(normalized_fixture_sha256(File.join(modern, basename))).to eq(expected)
    end
  end
end
