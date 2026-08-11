require 'spec_helper'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'
previous_autorun = defined?($autorun) ? $autorun : nil
$autorun = false
require_relative '../src/frontend/frontend_modern_source'
$autorun = previous_autorun

describe 'Modern value returns' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'value-return.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_parse_error(source, message, offending, occurrence: :first, offset: nil)
    expect do
      parse(source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      start = offset || (occurrence == :last ? source.rindex(offending) : source.index(offending))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'builds a frozen wrapper with immutable source metadata from return through the value' do
    source = "def main():String\nreturn \"value\"# adjacent\nend\n"
    value_return = parse(source).declarations.fetch(0).body_items.fetch(0)

    expect(value_return).to be_a(DabModernBootstrapValueReturn)
    expect(value_return.kind).to eq(:value_return)
    expect(value_return).to be_frozen
    expect(value_return.source_parts).to be_frozen
    expect(value_return.source_parts.map(&:to_s)).to eq(['return', ' ', '"value"'])
    expect(value_return.separator_token.kind).to eq(:line_comment)
    expect(source.byteslice(value_return.source_span.start_offset...value_return.source_span.end_offset)).to eq(
      'return "value"'
    )
  end

  it 'accepts every existing literal, earlier same-function local, and one-level String length result' do
    source = <<~DAB
      def literals()
      return nil
      return true
      return false
      return 1
      return "text"
      end
      def locals():String
      let fixed = "fixed"
      var mutable = nil
      mutable = "latest"
      return fixed
      return mutable
      end
      def property():Int32
      return "abc".length
      end
      def call():Int32
      return "é".length\t( \t)
      end
    DAB
    document = parse(source)

    expect(document.declarations.flat_map(&:body_items).map(&:kind)).to include(:value_return)
    expect { document.lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'uses current literal assignability without converting the returned source value' do
    accepted = {
      'String' => '"text"',
      'Fixnum' => '1',
      'Boolean' => 'true',
      'Uint8' => '1',
      'Uint16' => '1',
      'Uint32' => '1',
      'Uint64' => '1',
      'Int8' => '1',
      'Int16' => '1',
      'Int32' => '1',
      'Int64' => '1',
      'IntPtr' => 'nil',
      'NilClass' => 'nil',
      'Float' => 'nil',
    }
    expect(accepted.keys).to eq(DabModernBootstrapParser::SUPPORTED_TYPE_NAMES)

    expected_classes = {
      '"text"' => DabNodeLiteralString,
      '1' => DabNodeLiteralNumber,
      'true' => DabNodeLiteralBoolean,
      'nil' => DabNodeLiteralNil,
    }
    accepted.each do |type_name, value|
      function = parse("def value():#{type_name}\nreturn #{value}\nend\n").lower_into(DabNodeUnit.new)
      returned = function.blocks[0].all_nodes(DabNodeReturn).fetch(0).value
      expect(returned).to be_a(expected_classes.fetch(value)), type_name
    end
    numeric = parse("def value():Int32\nreturn 1\nend\n").lower_into(DabNodeUnit.new)
    expect(numeric.blocks[0].all_nodes(DabNodeReturn).fetch(0).value.my_type.type_string).to eq('Fixnum')
  end

  it 'checks the complete supported return-contract matrix with Modern literal-flow types' do
    numeric_types = %w[Fixnum Uint8 Uint16 Uint32 Uint64 Int8 Int16 Int32 Int64]
    cases = {
      'nil' => ['NilClass', DabModernBootstrapParser::SUPPORTED_TYPE_NAMES],
      'true' => ['Boolean', ['Boolean']],
      '1' => ['Fixnum', numeric_types],
      '"text"' => ['String', ['String']],
    }

    cases.each do |value, (actual_type, accepted_types)|
      DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.each do |expected_type|
        source = "def value():#{expected_type}\nreturn #{value}\nend\n"
        if accepted_types.include?(expected_type)
          expect { parse(source) }.not_to raise_error, "#{actual_type} -> #{expected_type}"
        else
          expect { parse(source) }.to raise_error(
            DabModernBootstrapParseError,
            "cannot return Modern value of type #{actual_type} from function \"value\" " \
            "with declared return type #{expected_type}"
          ), "#{actual_type} -> #{expected_type}"
        end
      end
    end
  end

  it 'uses declared types for annotated locals and latest literal flow for unannotated locals' do
    accepted = <<~DAB
      def declared():String
      var value : String = nil
      return value
      end
      def flowed():String
      var value = nil
      value = "text"
      return value
      end
    DAB
    expect { parse(accepted) }.not_to raise_error

    declared_mismatch = <<~DAB
      def declared():NilClass
      var value : String = nil
      return value
      end
    DAB
    expect_parse_error(
      declared_mismatch,
      'cannot return Modern value of type String from function "declared" with declared return type NilClass',
      'value',
      occurrence: :last
    )

    flow_mismatch = <<~DAB
      def flowed():NilClass
      var value = nil
      value = "text"
      return value
      end
    DAB
    expect_parse_error(
      flow_mismatch,
      'cannot return Modern value of type String from function "flowed" with declared return type NilClass',
      'value',
      occurrence: :last
    )
  end

  it 'contains String length results to exact Int32 or an omitted Object contract' do
    expect do
      parse("def exact():Int32\nreturn \"abc\".length\nend\n").lower_into(DabNodeUnit.new)
    end.not_to raise_error
    expect do
      parse("def omitted()\nreturn \"abc\".length()\nend\n").lower_into(DabNodeUnit.new)
    end.not_to raise_error

    %w[Fixnum Uint32 Int64 String].each do |type_name|
      source = "def mismatch():#{type_name}\nreturn \"abc\".length\nend\n"
      expect do
        parse(source).lower_into(DabNodeUnit.new)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(
          'cannot return Modern value of type Int32 from function "mismatch" ' \
          "with declared return type #{type_name}"
        )
        expression = '"abc".length'
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(expression)
      }
    end
  end

  it 'requires exactly one ASCII space after return and an immediate approved separator after the value' do
    bare_message = DabModernBootstrapParser::EXPECT_BARE_RETURN_SEPARATOR_MESSAGE
    value_message = DabModernBootstrapParser::EXPECT_VALUE_RETURN_SEPARATOR_MESSAGE
    expect_parse_error("def main()\nreturn\t1\nend\n", bare_message, "\t")
    double_space = "def main()\nreturn  1\nend\n"
    expect_parse_error(
      double_space,
      bare_message,
      ' ',
      offset: double_space.index('return') + 6
    )

    {
      'space' => ["def main()\nreturn 1 \nend\n", ' '],
      'TAB' => ["def main()\nreturn 1\t\nend\n", "\t"],
      'operator' => ["def main()\nreturn 1+2\nend\n", '+'],
      'chaining' => ["def main()\nreturn \"x\".length.to_s\nend\n", '.'],
    }.each_value do |source, offending|
      expect_parse_error(
        source,
        value_message,
        offending,
        occurrence: :last
      )
    end

    eof_source = "def main()\nreturn 1"
    expect_parse_error(eof_source, value_message, '', occurrence: :last)
    ["\r", "\r\n"].each do |ending|
      source = "def main()\nreturn 1#{ending}end\n"
      expect_parse_error(source, DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE, ending)
    end
  end

  it 'keeps parameters, calls, read-before and broader expressions outside the value subset' do
    cases = {
      'parameter' => ["def value(arg:String):String\nreturn arg\nend\n", 'arg'],
      'unknown local' => ["def value():String\nreturn missing\nend\n", 'missing'],
      'read before' => ["def value():String\nreturn later\nlet later = \"x\"\nend\n", 'later'],
      'ordinary call' => ["def helper():String\nreturn \"x\"\nend\ndef main():String\nreturn helper()\nend\n", 'helper'],
      'member on local' => ["def main():Int32\nlet value = \"x\"\nreturn value.length\nend\n", 'value'],
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

  it 'preserves structural, local, Ring, declaration, member, and lowering transaction order' do
    structural = "def main():String\nreturn 1\nprint(,)\nend\n"
    expect { parse(structural) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    local = "def main():String\nreturn 1\nlet value:String = 1\nend\n"
    expect { parse(local) }.to raise_error(
      DabModernBootstrapParseError,
      'cannot return Modern value of type Fixnum from function "main" with declared return type String'
    )

    source = "def main():String\nreturn \"x\".length\nend\n"
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('main', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    expect { parse(source).lower_into(unit) }.to raise_error(DabModernBootstrapParseError)
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'lowers the original value once and leaves consumed member destination ownership to return SSA' do
    source = <<~DAB
      def literal():Fixnum
      return 1
      end
      def local():String
      let value = "x"
      return value
      end
      def member():Int32
      return "abc".length
      end
    DAB
    functions = parse(source).lower_into(DabNodeUnit.new)
    literal_return, local_return, member_return = functions.map do |function|
      function.blocks[0].all_nodes(DabNodeReturn).fetch(0)
    end

    expect(literal_return.value).to be_a(DabNodeLiteralNumber)
    expect(local_return.value).to be_a(DabNodeLocalVar)
    expect(member_return.value).to be_a(DabNodeModernMemberResult)
    expect(member_return.value.instance_variable_get(:@consumed)).to be(true)

    member = functions.fetch(2)
    loop do
      break unless member.run_late_lower_processors!
    end
    expect(member_return.value.output_register).to be_nil
  end

  it 'keeps bare-return parsing and Nil lowering unchanged' do
    source = "def main()\nreturn\nend\n"
    bare_return = parse(source).declarations.fetch(0).body_items.fetch(0)
    lowered = parse(source).lower_into(DabNodeUnit.new).blocks[0].all_nodes(DabNodeReturn).fetch(0)

    expect(bare_return).to be_a(DabModernBootstrapBareReturn)
    expect(bare_return.source_parts.map(&:to_s)).to eq(['return'])
    expect(lowered.value).to be_a(DabNodeLiteralNil)
  end

  it 'locks the migrated 0082 boundary and primary 0083 through 0085 fixtures' do
    fixtures = (82..85).to_h do |number|
      pattern = File.join(root, sprintf('test/modern_source/%04d_*.dabmtest', number))
      [number, DabModernSourceFixture.load(Dir.glob(pattern).fetch(0))]
    end
    read_before = fixtures.fetch(82)
    success = fixtures.fetch(83)
    mismatch = fixtures.fetch(84)
    call_result = fixtures.fetch(85)

    expect(read_before.expected_stderr).to eq(
      'compiler: 0082_return_local_read_before.dabm:2:7: error: ' \
      "#{DabModernBootstrapParseError::GENERIC_MESSAGE}\n"
    )
    expect([success.expected_status, success.expected_application_stdout]).to eq(
      [0, "helper-before\nmain-after-helper\n"]
    )
    expect(success.expected_stdout).to include('RETURN RNIL', 'RETURN R0', 'RETURN R1')
    expect(success.expected_stdout.scan('INSTCALL R1, R0, S33').length).to eq(2)
    expect(success.expected_stdout).not_to include(
      'nil-tail',
      'boolean-tail',
      'integer-tail',
      'string-tail',
      'fixed-tail',
      'mutable-tail',
      'property-tail',
      'call-tail',
      'helper-after',
      'main-after-return'
    )
    expect(mismatch.expected_stderr).to eq(
      'compiler: 0084_return_contract_mismatch.dabm:2:7: error: ' \
      "cannot return Modern value of type Fixnum from function \"main\" with declared return type String\n"
    )
    expect(call_result.expected_stderr).to eq(
      'compiler: 0085_call_result_return_remains_unsupported.dabm:5:7: error: ' \
      "#{DabModernBootstrapParseError::GENERIC_MESSAGE}\n"
    )
  end
end
