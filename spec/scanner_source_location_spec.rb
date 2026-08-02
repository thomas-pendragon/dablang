require 'spec_helper'

require_relative '../src/compiler/_requires'

describe 'shared scanner and source locations' do
  let(:legacy_source_unit) do
    DabSourceUnit.new(input: 'sample.dab', syntax_profile: DabSyntaxProfile::LEGACY)
  end

  it 'retains one frozen source-unit identity through scanner locations and spans' do
    scanner = DabScanner.new('identifier', source_unit: legacy_source_unit)
    start_location = scanner.current_location
    scanner.advance!(scanner.content.length)
    span = scanner.source_span(start_location.offset, scanner.position)

    expect(scanner.source_unit).to equal(legacy_source_unit)
    expect(start_location.source_unit).to equal(legacy_source_unit)
    expect(span.source_unit).to equal(legacy_source_unit)
    expect(span.start_location).to equal(start_location)
    expect(scanner.location_at(start_location.offset)).to equal(start_location)
    expect(span.end_location.offset).to eq 10
    expect(start_location).to be_frozen
    expect(span).to be_frozen
  end

  it 'keeps the characterized Legacy line, column, and half-open offset boundaries' do
    cases = {
      'alpha beta' => [1, 6, 6, 10],
      "alpha\nbeta" => [2, 0, 6, 10],
      "alpha\rbeta" => [1, 6, 6, 10],
      "alpha\r\nbeta" => [2, 0, 7, 11],
      "alpha\tbeta" => [1, 6, 6, 10],
    }

    cases.each do |source, (line, column, start_offset, end_offset)|
      stream = DabProgramStream.new(source, source_unit: legacy_source_unit)
      stream.read_identifier
      token = stream.read_identifier

      expect(token.to_s).to eq 'beta'
      expect(token.source_line).to eq line
      expect(token.source_column).to eq column
      expect(token.source_cstart).to eq start_offset
      expect(token.source_cend).to eq end_offset
      expect(token.source_span.source_unit).to equal(legacy_source_unit)
    end
  end

  it 'keeps LF boundary accounting and one-column tab and carriage-return accounting explicit' do
    scanner = DabScanner.new("a\t\r\nb", source_unit: legacy_source_unit)

    expect(scanner.location_at(0).to_h).to eq(offset: 0, line: 1, column: 0)
    expect(scanner.location_at(1).to_h).to eq(offset: 1, line: 1, column: 1)
    expect(scanner.location_at(2).to_h).to eq(offset: 2, line: 1, column: 2)
    expect(scanner.location_at(3).to_h).to eq(offset: 3, line: 2, column: 0)
    expect(scanner.location_at(4).to_h).to eq(offset: 4, line: 2, column: 0)
    expect(scanner.location_at(5).to_h).to eq(offset: 5, line: 2, column: 1)
  end

  it 'preserves the input encoding and its existing String-index offset semantics' do
    utf8 = DabScanner.new('éx', source_unit: legacy_source_unit)
    binary = DabScanner.new('éx'.b, source_unit: legacy_source_unit)

    expect(utf8.content.encoding.name).to eq 'UTF-8'
    expect(utf8.content.length).to eq 2
    expect(utf8.content.bytesize).to eq 3
    expect(utf8.lookup).to eq 'é'
    expect(utf8.location_at(1).column).to eq 1

    expect(binary.content.encoding.name).to eq 'ASCII-8BIT'
    expect(binary.content.length).to eq 3
    expect(binary.lookup.bytes).to eq [195]
    expect(binary.location_at(1).column).to eq 1
  end

  it 'provides a stable EOF location and preserves EOF over-advance errors' do
    scanner = DabScanner.new('', source_unit: legacy_source_unit)

    expect(scanner).to be_eof
    expect(scanner.lookup).to eq ''
    expect(scanner.current_char).to be_nil
    expect(scanner.current_location.to_h).to eq(offset: 0, line: 1, column: 0)
    expect { scanner.advance! }.to raise_error(DabEndOfStreamError)
  end

  it 'preserves speculative lookahead rollback and explicit cursor commit' do
    context = DabBaseContext.new(DabParser.new('ifx', source_unit: legacy_source_unit))

    expect(context.on_subcontext { |subcontext| subcontext.read_keyword('if') }).to be false
    expect(context.stream.position).to eq 0

    subcontext = context.clone
    expect(subcontext.read_identifier).to eq 'ifx'
    expect(context.stream.position).to eq 0
    expect(subcontext.stream.source_unit).to equal(legacy_source_unit)

    context.merge!(subcontext)
    expect(context.stream.position).to eq 3
  end

  it 'attaches canonical spans to the Legacy token readers without changing token values' do
    cases = [
      [:read_keyword, ['func'], ' func ', 'func', 1, 5],
      [:read_identifier, [], ' name ', 'name', 1, 5],
      [:read_class_identifier, [], ' Class ', 'Class', 1, 6],
      [:read_classvar, [], ' @field ', '@field', 1, 7],
      [:read_statclassvar, [], ' @@field ', '@@field', 1, 8],
      [:read_operator, ['=='], ' == ', '==', 1, 3],
      [:read_string, [], ' "a\\n" ', "a\n", 1, 6],
      [:read_binary_number, [], ' 0b101 ', '101', 1, 6],
      [:read_float, [], ' -1.5 ', '-1.5', 1, 5],
      [:read_number, [], ' -15 ', '-15', 1, 4],
    ]

    cases.each do |method, arguments, source, value, start_offset, end_offset|
      stream = DabProgramStream.new(source, source_unit: legacy_source_unit)
      token = stream.send(method, *arguments)

      expect(token.to_s).to eq value
      expect(token.source_cstart).to eq start_offset
      expect(token.source_cend).to eq end_offset
      expect(token.source_span).to be_frozen
      expect(token.source_span.source_unit).to equal(legacy_source_unit)
    end
  end

  it 'keeps malformed comments and line comments without a terminating LF at the established EOF boundary' do
    ['/* unterminated', '# unterminated', '// unterminated'].each do |source|
      expect { DabParser.new(source).non_comment_content }.to raise_error(DabEndOfStreamError)
    end
  end

  it 'keeps compiler fallback diagnostics at line zero while retaining source-unit identity' do
    {
      '$' => DabUnknownTokenError,
      '/* unterminated' => DabUnexpectedEOFError,
    }.each do |source, error_class|
      stream = DabProgramStream.new(source, source_unit: legacy_source_unit)
      error = DabCompiler.new(stream).program.errors.fetch(0)

      expect(error).to be_a(error_class)
      expect(error.source.source_file).to eq 'sample.dab'
      expect(error.source.source_line).to eq 0
      expect(error.source.source_cstart).to eq 0
      expect(error.source.source_cend).to eq 0
      expect(error.source.source_span.source_unit).to equal(legacy_source_unit)
    end
  end

  it 'allows the syntax-neutral scanner to carry Modern identity without implementing Modern parsing' do
    modern_source_unit = DabSourceUnit.new(input: 'future.dabm', syntax_profile: DabSyntaxProfile::MODERN)
    scanner = DabScanner.new('future source', source_unit: modern_source_unit)

    expect(scanner.source_unit).to equal(modern_source_unit)
    expect(scanner.current_location.source_unit).to equal(modern_source_unit)
    expect do
      DabProgramStream.new('future source', source_unit: modern_source_unit)
    end.to raise_error(
      DabUnsupportedSyntaxProfileError,
      'unsupported Dab syntax profile "modern": parser is not implemented'
    )
  end
end
