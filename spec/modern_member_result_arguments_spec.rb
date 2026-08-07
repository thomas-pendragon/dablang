require 'spec_helper'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern one-level member-result arguments' do
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'member-result-arguments.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end
  let(:puts_signature) do
    {
      arguments: [{name: 'value', type: 'Object'}.freeze].freeze,
      return_type: 'Object',
    }.freeze
  end

  def parse(source, member_result_byte_limit: DabModernBootstrapDocument::INT32_MAX)
    DabModernBootstrapParser.new(
      source.b,
      source_unit: source_unit,
      member_result_byte_limit: member_result_byte_limit
    ).parse
  end

  def puts_stub
    DabNodeFunctionStub.new('puts', nil, is_static: false, ring_signature: puts_signature)
  end

  def instance_stub(name)
    DabNodeFunctionStub.new(name, nil, is_static: false)
  end

  it 'parses property and explicit String length arguments with exact outer whitespace boundaries' do
    source = <<~DAB
      def pair(first:Int32,second:Int32)
      end
      def main
      pair("a".length , "bb".length\t( ) )
      end
    DAB
    call = parse(source).declarations.fetch(1).body_items.fetch(0)

    expect(call.arguments).to all(be_a(DabModernBootstrapLiteralMemberCall))
    expect(call.arguments.map(&:property_style?)).to eq([true, false])
    expect(call.arguments.map { |argument| argument.receiver_token.value }).to eq(%w[a bb])
    expect(call.arguments.map { |argument| argument.callable_name.text }).to eq(%w[length length])
    expect(call.source_tokens.map(&:text).join).to eq("pair(\"a\".length , \"bb\".length\t( ) )")
    expect(call.arguments.fetch(0).source_span.end_offset).to eq(source.index('length ,') + 'length'.length)
  end

  it 'accepts print, artifact-confirmed puts, and exact-Int32 same-document consumers' do
    source = <<~DAB
      def sink(value:Int32)
      end
      def main
      print("a".length)
      puts("bb".length())
      sink("ccc".length)
      end
    DAB
    unit = DabNodeUnit.new
    unit.add_function(puts_stub)

    functions = parse(source).lower_into(unit)
    calls = functions.fetch(1).blocks[0].all_nodes(DabNodeCall)
    expect(calls.map(&:real_identifier)).to eq(%w[print puts sink])
    expect(calls.flat_map(&:args)).to all(be_a(DabNodeModernMemberResult))
  end

  it 'contains newly accepted print nesting to exactly one total argument without changing literal-only print' do
    expect(parse("def main\nprint()\nprint(1,2)\nend\n").lower_into(DabNodeUnit.new)).to be_a(DabNodeFunction)

    source = "def main\nprint(1,\"x\".length)\nend\n"
    expect do
      parse(source).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('incorrect Modern call arity for "print": got 2, expected 1')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.index('print'), source.index(")\n") + 1]
      )
    }
  end

  it 'allows member results only for exact Int32 same-document parameters' do
    %w[Fixnum Uint32 Int64 String].each do |type|
      source = "def sink(value:#{type})\nend\ndef main\nsink(\"abc\".length)\nend\n"
      expect do
        parse(source).lower_into(DabNodeUnit.new)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(
          "cannot pass Modern argument of type Int32 to parameter \"value\" of type #{type} in call \"sink\""
        )
        expression = '"abc".length'
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [source.index(expression), source.index(expression) + expression.bytesize]
        )
      }
    end
  end

  it 'preflights outer target and arity before inner capability, then inner capability before type' do
    cases = [
      [
        "def main\nmissing(\"x\".missing)\nend\n",
        'unknown Modern call target "missing"',
      ],
      [
        "def sink(value:Int32)\nend\ndef main\nsink(\"x\".missing,1)\nend\n",
        'incorrect Modern call arity for "sink": got 2, expected 1',
      ],
      [
        "def sink(value:String)\nend\ndef main\nsink(\"x\".missing)\nend\n",
        'unknown Modern member target "String#missing"',
      ],
    ]

    cases.each do |source, message|
      expect { parse(source).lower_into(DabNodeUnit.new) }.to raise_error(
        DabModernBootstrapParseError,
        message
      )
    end
  end

  it 'fails closed on lower-Ring String length overrides before the exact type check' do
    source = "def sink(value:String)\nend\ndef main\nsink(\"x\".length)\nend\n"
    unit = DabNodeUnit.new
    unit.add_class(DabNodeClassDefinition.new('String', nil, [instance_stub('length')]))

    expect { parse(source).lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unsupported Modern member target "String#length" in the R40 dot/property-call subset'
    )
  end

  it 'rejects decoded byte counts beyond exact Int32 before lowering with the full expression span' do
    expect(DabModernBootstrapDocument::INT32_MAX).to eq(2_147_483_647)
    source = "def main\nprint(\"abcd\".length)\nend\n"
    expect(parse(source).lower_into(DabNodeUnit.new)).to be_a(DabNodeFunction)

    expect do
      parse(source, member_result_byte_limit: 3).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'Modern String#length result exceeds exact Int32 byte-count range 0..2147483647'
      )
      expression = '"abcd".length'
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.index(expression), source.index(expression) + expression.bytesize]
      )
    }
  end

  it 'keeps standalone M7 allocation while consumed results defer ownership to the outer argument register' do
    source = <<~DAB
      def main
      "a".length
      print("bb".length)
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    results = function.all_nodes(DabNodeModernMemberResult)

    loop do
      break unless function.run_late_lower_processors!
    end

    expect(results.map(&:output_register)).to eq([0, nil])
  end

  it 'keeps the complete lower unit unchanged when a later nested argument fails preflight' do
    unit = DabNodeUnit.new
    unit.add_function(puts_stub)
    original_functions = unit.functions.to_a
    original_classes = unit.classes.to_a
    original_constants = unit.constants.to_a
    source = <<~DAB
      def first
      print("a".length)
      end
      def second
      print("b".missing)
      end
    DAB

    expect { parse(source).lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern member target "String#missing"'
    )
    expect(unit.functions.to_a).to eq(original_functions)
    expect(unit.classes.to_a).to eq(original_classes)
    expect(unit.constants.to_a).to eq(original_constants)
  end
end
