require 'spec_helper'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern callable suffix lexical infrastructure' do
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'callable-suffixes.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end
  let(:composer) { DabModernCallableNameComposer.new }

  def scan(source)
    scanner = DabModernBootstrapScanner.new(source.b, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end
    tokens
  end

  it 'emits exact one-byte question_mark and bang tokens outside Strings and hash comments' do
    tokens = scan("ready? save! \"opaque?!\" # opaque?!\n# second opaque?!\n")

    expect(tokens.map(&:kind)).to eq(
      %i[
        identifier question_mark space identifier bang space string space line_comment line_feed
        line_comment line_feed eof
      ]
    )
    punctuation = tokens.select { |token| %i[question_mark bang].include?(token.kind) }
    expect(punctuation.map(&:text)).to eq(['?', '!'])
    expect(punctuation.map { |token| [token.source_span.start_offset, token.source_span.end_offset] }).to eq(
      [[5, 6], [11, 12]]
    )
    expect(tokens.fetch(6).value).to eq('opaque?!')
    expect(tokens.fetch(8).text).to eq('# opaque?!')
    expect(tokens.fetch(10).text).to eq('# second opaque?!')
    expect(tokens).to all(satisfy { |token| token.source_span.source_unit.equal?(source_unit) })
  end

  it 'retains the unchanged ASCII base-identifier boundary' do
    tokens = scan("AZ_09 é?\n")

    expect(tokens.map(&:kind)).to eq(
      %i[identifier space unsupported unsupported question_mark line_feed eof]
    )
    expect(tokens.map(&:text)).to eq(['AZ_09', ' ', "\xC3".b, "\xA9".b, '?', "\n", ''])
  end

  it 'composes zero or one adjacent suffix with exact base, suffix, and composite spans' do
    plain_base = scan('plain').fetch(0)
    plain = composer.compose(plain_base)
    expect(plain.text).to eq('plain')
    expect(plain.base_token).to equal(plain_base)
    expect(plain.suffix_token).to be_nil
    expect(plain.base_source_span).to equal(plain_base.source_span)
    expect(plain.suffix_source_span).to be_nil
    expect([plain.source_span.start_offset, plain.source_span.end_offset]).to eq([0, 5])
    expect(plain.source_parts.map(&:to_s)).to eq(['plain'])

    %w[ready? save!].each do |source|
      base_token, suffix_token = scan(source).first(2)
      name = composer.compose(base_token, suffix_token)

      expect(composer.adjacent_suffix?(base_token, suffix_token)).to be true
      expect(name.text).to eq(source)
      expect(name.base_token).to equal(base_token)
      expect(name.suffix_token).to equal(suffix_token)
      expect(name.base_source_span).to equal(base_token.source_span)
      expect(name.suffix_source_span).to equal(suffix_token.source_span)
      expect([name.source_span.start_offset, name.source_span.end_offset]).to eq([0, source.bytesize])
      expect(name.source_parts.map(&:to_s)).to eq([source[0...-1], source[-1]])
      expect(name.source_string.source_span).to equal(name.source_span)
    end
  end

  it 'does not compose across whitespace, reserved bases, or more than one suffix token' do
    spaced_base, _space, spaced_suffix = scan('ready ?').first(3)
    expect(composer.adjacent_suffix?(spaced_base, spaced_suffix)).to be false
    expect { composer.compose(spaced_base, spaced_suffix) }
      .to raise_error(ArgumentError, /one adjacent question_mark or bang token/)

    reserved_base, reserved_suffix = scan('nil?').first(2)
    expect(composer.adjacent_suffix?(reserved_base, reserved_suffix)).to be false
    expect { composer.compose(reserved_base, reserved_suffix) }
      .to raise_error(ArgumentError, /base must be an identifier token/)

    %w[foo?? foo!! foo?! foo!?].each do |source|
      base_token, first_suffix, second_suffix = scan(source).first(3)
      name = composer.compose(base_token, first_suffix)

      expect(name.text).to eq(source.byteslice(0, 4))
      expect(second_suffix.text).to eq(source.byteslice(4, 1))
      expect(second_suffix.source_span.start_offset).to eq(name.source_span.end_offset)
    end
  end

  it 'keeps excluded suffix uses on the generic fallback with their prior exact spans' do
    cases = {
      'literal predicate' => ["def main\nnil?\nend\n", [12, 13]],
      'unary bang' => ["def main\n!false\nend\n", [9, 10]],
      'repeated suffix' => ["def main??\nend\n", [9, 10]],
      'spaced suffix' => ["def main ?\nend\n", [8, 9]],
      'setter-like boundary' => ["def main\nfoo?=\nend\n", [9, 12]],
      'bang before identifier' => ["def main\nfoo!bar\nend\n", [9, 12]],
      'type-like boundary' => ["def main\nType?\nend\n", [9, 13]],
      'safe-navigation-like boundary' => ["def main\nvalue?.x\nend\n", [9, 14]],
      'label-like boundary' => ["def main\ntop?:\nend\n", [9, 12]],
      'inequality-like boundary' => ["def main\n1!=2\nend\n", [10, 11]],
    }

    cases.each do |description, (source, span)|
      expect do
        DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(span), description
        expect(error.source_span.source_unit).to equal(source_unit)
      }
    end
  end

  it 'keeps suffix bytes opaque in accepted Modern Strings and hash comments' do
    source = "# ?!\ndef main\n\"?!\";# ?!\nend\n".b
    declaration = DabModernBootstrapParser.new(source, source_unit: source_unit).parse
    unit = DabNodeUnit.new

    function = declaration.lower_into(unit)

    expect(function.identifier).to eq('main')
    expect(function.blocks[0]).not_to be_empty
  end

  it 'leaves the broad Legacy terminal-question identifier precedent unchanged' do
    question_parser = DabParser.new('ready??')
    bang_parser = DabParser.new('save!')

    expect(question_parser.read_identifier).to eq('ready?')
    expect(question_parser.read_identifier).to be_nil
    expect(bang_parser.read_identifier).to eq('save')
    expect(bang_parser.read_identifier).to be_nil
  end
end
