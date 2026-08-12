require 'spec_helper'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern String interpolation' do
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'interpolation.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def scan(source)
    DabModernBootstrapScanner.new(source.b, source_unit: source_unit).next_token
  end

  def interpolation(source)
    scan(source).value
  end

  it 'retains an immutable scanner wrapper and exact source parts for multiple and adjacent splices' do
    source = "\"left \#{first}\#{second} right\""
    token = scan(source)
    value = token.value

    expect(token.kind).to eq(:interpolated_string)
    expect([token.text, token.source_span.start_offset, token.source_span.end_offset]).to eq(
      [source.b, 0, source.bytesize]
    )
    expect(value).to be_a(DabModernBootstrapInterpolatedString)
    expect(value).to be_frozen
    expect(value.parts).to all(be_frozen)
    expect(value.splices).to all(be_frozen)
    expect(value.splices.map(&:name)).to eq(%w[first second])
    expect(value.source_tokens.map(&:text).join).to eq(source)
    expect(value.source_tokens.map { |part| [part.kind, part.source_span.start_offset, part.source_span.end_offset] }).to eq(
      [
        [:string_quote, 0, 1],
        [:string_text, 1, 6],
        [:interpolation_opener, 6, 8],
        [:identifier, 8, 13],
        [:interpolation_closer, 13, 14],
        [:string_text, 14, 14],
        [:interpolation_opener, 14, 16],
        [:identifier, 16, 22],
        [:interpolation_closer, 22, 23],
        [:string_text, 23, 29],
        [:string_quote, 29, 30],
      ]
    )
  end

  it 'keeps escaped openers literal, honors backslash parity, and never rescans decoded escapes' do
    literal = scan('"literal \\#{name} and \\u0023{name}"')
    even = scan('"\\\\#{name}"')
    odd = scan('"\\\\\\#{name}"')

    expect([literal.kind, literal.value]).to eq([:string, "literal \#{name} and \#{name}".b])
    expect([even.kind, even.value.splices.map(&:name)]).to eq([:interpolated_string, ['name']])
    expect([odd.kind, odd.value]).to eq([:string, '\\#{name}'.b])
  end

  it 'emits the two structural diagnostic families with present-token and EOF spans' do
    cases = {
      "\"\#{}\"" => [
        'invalid Modern String interpolation: expected an ASCII local identifier immediately after "#{"',
        3,
        4,
      ],
      "\"\#{ nil}\"" => [
        'invalid Modern String interpolation: expected an ASCII local identifier immediately after "#{"',
        3,
        4,
      ],
      "\"\#{nil}\"" => [
        'invalid Modern String interpolation: expected an ASCII local identifier immediately after "#{"',
        3,
        6,
      ],
      "\"\#{name()}\"" => [
        'invalid Modern String interpolation: expected "}" immediately after local identifier',
        7,
        8,
      ],
      '"#{name' => [
        'invalid Modern String interpolation: expected "}" immediately after local identifier',
        7,
        7,
      ],
    }

    cases.each do |source, (message, start_offset, end_offset)|
      token = scan(source)
      expect(token.kind).to eq(:unsupported), source
      expect(token.diagnostic_message).to eq(message), source
      expect([token.source_span.start_offset, token.source_span.end_offset]).to eq(
        [start_offset, end_offset]
      ), source
    end
  end

  it 'accepts only an earlier same-function local whose latest preceding flow is exact String' do
    accepted = <<~DAB
      def main()
      let fixed = "fixed"
      var flowed = nil
      flowed = "flowed"
      print("\#{fixed}:\#{flowed}")
      end
    DAB
    expect { parse(accepted) }.not_to raise_error

    cases = {
      unknown: [
        "def main()\nprint(\"\#{missing}\")\nend\n",
        'unknown Modern interpolation local "missing"; expected an earlier same-function local binding',
        'missing',
      ],
      read_before: [
        "def main()\nprint(\"\#{later}\")\nlet later = \"later\"\nend\n",
        'unknown Modern interpolation local "later"; expected an earlier same-function local binding',
        'later',
      ],
      parameter: [
        "def main(value:String)\nprint(\"\#{value}\")\nend\n",
        'unsupported Modern interpolation value "value": function parameters are not part of simple interpolation',
        'value',
      ],
      non_string: [
        "def main()\nvar value = \"first\"\nvalue = 1\nprint(\"\#{value}\")\nend\n",
        'cannot interpolate Modern local "value" of type Fixnum; simple interpolation requires exact String',
        'value',
      ],
      cross_function: [
        "def first()\nlet value = \"first\"\nend\ndef second()\nprint(\"\#{value}\")\nend\n",
        'unknown Modern interpolation local "value"; expected an earlier same-function local binding',
        'value',
      ],
    }

    cases.each do |description, (source, message, name)|
      expect { parse(source) }.to raise_error(DabModernBootstrapParseError, message) { |error|
        start_offset = source.index("\#{#{name}}") + 2
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [start_offset, start_offset + name.bytesize]
        )
      }, description.to_s
    end
  end

  it 'checks splices left-to-right before enclosing call and return validation' do
    source = <<~DAB
      def main():Fixnum
      let number = 1
      missing("\#{unknown}:\#{number}")
      return "\#{number}"
      end
    DAB

    expect { parse(source) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern interpolation local "unknown"; expected an earlier same-function local binding'
    )
  end

  it 'admits only the five existing String value slots and leaves interpolated member receivers closed' do
    source = <<~DAB
      def sink(value:String)
      end
      def result():String
      let base = "return"
      return "\#{base}"
      end
      def main()
      let base = "value"
      "\#{base}"
      let fixed = "\#{base}"
      var mutable = "\#{fixed}"
      mutable = "\#{mutable}"
      sink("\#{mutable}")
      end
    DAB
    document = parse(source)
    expect { document.lower_into(DabNodeUnit.new) }.not_to raise_error

    receiver = "def main()\nlet value = \"x\"\n\"\#{value}\".length\nend\n"
    expect { parse(receiver) }.to raise_error(DabModernBootstrapParseError)
  end

  it 'lowers to one exact-String node, reads each splice once, and omits empty constants and conversion calls' do
    source = <<~DAB
      def main()
      let first = "first"
      let second = "second"
      print("\#{first}\#{second}:\#{first}")
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    interpolation_node = function.all_nodes(DabNodeModernInterpolatedString).fetch(0)

    expect(interpolation_node.my_type.type_string).to eq('String')
    expect(interpolation_node.formatted_source(syntax_profile: DabSyntaxProfile::MODERN)).to eq(
      "\"\#{first}\#{second}:\#{first}\""
    )
    expect(interpolation_node.all_nodes(DabNodeModernStringAppend).length).to eq(3)
    expect(interpolation_node.all_nodes(DabNodeLocalVar).map(&:real_identifier)).to eq(
      %w[first second first]
    )
    expect(interpolation_node.all_nodes(DabNodeLiteralString).map(&:constant_value)).to eq([':'])
    expect(interpolation_node.all_nodes(DabNodeInstanceCall)).to be_empty
    expect(interpolation_node.all_nodes(DabNodeCall)).to be_empty
  end

  it 'reads a reassignment interpolation before recording its exact-String result' do
    source = <<~DAB
      def main()
      var value = "before"
      value = "\#{value}!"
      print("\#{value}")
      end
    DAB
    document = parse(source)
    function = document.lower_into(DabNodeUnit.new)
    setter = function.all_nodes(DabNodeSetLocalVar).reject { |node| node.is_a?(DabNodeDefineLocalVar) }.fetch(0)
    read = setter.all_nodes(DabNodeLocalVar).fetch(0)

    expect(read.real_identifier).to eq('value')
    expect(read.last_var_setter).to be_a(DabNodeDefineLocalVar)
  end
end
