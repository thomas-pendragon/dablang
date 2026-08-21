require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern Regex matching in case' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:internal_match_target) { DabTypeRegex::INTERNAL_MATCH_TARGET }
  let(:source_unit) do
    DabSourceUnit.new(input: 'regex-case-matching.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def lower(source)
    parse(source).lower_into(DabNodeUnit.new)
  end

  def expect_error(source, message, subject)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      case_start = source.index("case #{subject}")
      start = case_start ? case_start + 'case '.bytesize : source.index(subject)
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset])
        .to eq([start, start + subject.bytesize])
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'admits Regex only at the first and after-comma when-pattern boundaries' do
    source = <<~DAB
      def main(subject:String)
      case subject
      when /first/, "ordinary", /last/
      end
      end
    DAB
    clause = parse(source).declarations.fetch(0).body_items.fetch(0).when_clauses.fetch(0)

    expect(clause.patterns.map(&:kind)).to eq(%i[regex_literal string regex_literal])
    expect(DabModernBootstrapParser::LITERAL_KINDS).not_to include(:regex_literal)
    expect(DabModernBootstrapParser::VALUE_KINDS).not_to include(:regex_literal)

    invalid = "def main(subject:String)\ncase subject\nwhen /a/ /b/\nend\nend\n"
    expect { parse(invalid) }.to raise_error(DabModernBootstrapParseError) { |error|
      offset = invalid.index(' /b/')
      expect(error.message).to eq(DabModernBootstrapParser::EXPECT_WHEN_PATTERN_SEPARATOR_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([offset, offset + 1])
    }
  end

  it 'enables Regex at the first boundary within the when-clause parser itself' do
    parser = DabModernBootstrapParser.new("when /direct/\nend\n".b, source_unit: source_unit)
    clause = parser.send(:parse_when_clause, {})

    expect(clause.patterns.map(&:kind)).to eq([:regex_literal])
  end

  it 'retains strict Regex literal diagnostics when a when-pattern boundary enables value scanning' do
    source = "def main(subject:String)\ncase subject\nwhen /unterminated\nend\nend\n".b
    offset = source.index("\n", source.index('/'))
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('invalid Modern regular-expression literal: literal LF is not allowed')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([offset, offset + 1])
    }
  end

  it 'requires exact statically known String subjects for every complete case containing Regex' do
    invalid_subjects = {
      'nil' => 'NilClass',
      'true' => 'Boolean',
      '1' => 'Fixnum',
      '/subject/' => 'Regex',
      'unknown_type()' => 'Object',
    }
    invalid_subjects.each do |subject, actual_type|
      declaration = if subject == 'unknown_type()'
                      "def unknown_type()\nreturn \"value\"\nend\n"
                    else
                      ''
                    end
      source = "#{declaration}def main()\ncase #{subject}\nwhen /value/\nend\nend\n"
      expect_error(
        source,
        "invalid Modern Regex case subject: expected String, got #{actual_type}",
        subject
      )
    end
  end

  it 'accepts every established subject form only when its exact static type is String' do
    source = <<~'DAB'
      def produced():String
      return "call"
      end
      def main(parameter:String)
      let inferred = "local"
      var annotated : String = "mutable"
      case "literal"
      when /lit/
      end
      case "#{parameter}"
      when /parameter/
      end
      case inferred
      when /local/
      end
      case annotated
      when /mutable/
      end
      case parameter
      when /parameter/
      end
      case produced()
      when /call/
      end
      end
    DAB

    expect { parse(source) }.not_to raise_error
    expect { lower(source) }.not_to raise_error
  end

  it 'uses the complete subject span and rejects before lowering mutates a target unit' do
    source = "def main()\ncase missing()\nwhen /a/\nend\nend\n"
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)

    expect_error(source, 'unknown Modern call target "missing"', 'missing')
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty

    typed = "def main(value:Int32)\ncase value\nwhen /a/\nend\nend\n"
    expect_error(
      typed,
      'invalid Modern Regex case subject: expected String, got Int32',
      'value'
    )
  end

  it 'lowers Regex patterns to one source-unspellable instance target over existing INSTCALL' do
    function = lower(<<~DAB)
      def main(subject:String)
      case subject
      when "literal", /first/, /second/
      end
      end
    DAB
    calls = function.blocks[0].all_nodes(DabNodeInstanceCall)
    comparisons = calls.select { |call| call.real_identifier.to_s == '==' }
    matches = calls.select { |call| call.real_identifier.to_s == internal_match_target }
    constructors = calls.select { |call| call.real_identifier.to_s == 'new' }

    expect(comparisons.length).to eq(1)
    expect(matches.length).to eq(2)
    expect(constructors.length).to eq(2)
    expect(matches.map(&:value)).to all(be_a(DabNodeInstanceCall))
    expect(matches.map { |call| call.args.fetch(0).real_identifier.to_s }.uniq.length).to eq(1)
    expect(matches).to all(be_compiler_verified_target)
    expect(DabModernBootstrapCaseStatement::REGEX_MATCH_TARGET).to equal(internal_match_target)
    expect(DabTypeRegex.new).to have_function(internal_match_target)
    expect(DabTypeRegex.new).not_to have_function('matches?')
    expect(internal_match_target).to start_with('$')
  end

  it 'keeps written Regex annotations and public Regex matching members unavailable' do
    expect(DabModernBootstrapParser::SUPPORTED_TYPE_NAMES).not_to include('Regex')
    expect { DabType.parse('Regex') }.to raise_error(RuntimeError, 'Unknown type Regex')

    source = "def main\n/a/.matches?(\"a\")\nend\n"
    expect { parse(source).lower_into(DabNodeUnit.new) }
      .to raise_error(DabModernBootstrapParseError, 'unknown Modern member target "Regex#matches?"')
  end

  it 'keeps compiler preflight failures transactional ahead of missing Ring loading' do
    source = "def main\ncase 1\nwhen /a/\nend\nend\n"
    diagnostic = 'invalid Modern Regex case subject: expected String, got Fixnum'

    Dir.mktmpdir('dab-modern-regex-case') do |directory|
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
      expect(stderr).to include("#{source_path}:2:5: error: #{diagnostic}\n")
      expect(stderr).not_to include('missing.dabcb')
      expect(Dir.children(directory)).to eq(['invalid.dabm'])
    end
  end
end
