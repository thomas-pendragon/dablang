require 'spec_helper'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'
previous_autorun = defined?($autorun) ? $autorun : nil
$autorun = false
require_relative '../src/frontend/frontend_modern_source'
$autorun = previous_autorun

describe 'Modern parameter references' do
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'parameter-references.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end
  let(:root) { File.expand_path('..', __dir__) }
  let(:puts_signature) do
    {
      arguments: [{name: 'string', type: 'Object'}.freeze].freeze,
      return_type: 'Object',
    }.freeze
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def lower(source, unit = DabNodeUnit.new)
    parse(source).lower_into(unit)
  end

  def puts_stub
    DabNodeFunctionStub.new('puts', nil, is_static: false, ring_signature: puts_signature)
  end

  def expect_generic_error(source, offending, occurrence: :first)
    expect do
      lower(source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      start = occurrence == :last ? source.rindex(offending) : source.index(offending)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'uses every declared parameter type through existing call and return compatibility' do
    sources = DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.each_with_index.map do |type_name, index|
      <<~DAB
        def sink#{index}(value:#{type_name}):#{type_name}
        return value
        end
        def relay#{index}(value:#{type_name}):#{type_name}
        sink#{index}(value)
        return value
        end
      DAB
    end
    functions = lower(sources.join)

    expect(functions.length).to eq(DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.length * 2)
    functions.each_slice(2).with_index do |(sink, relay), index|
      type_name = DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.fetch(index)
      expect([sink.arglist.to_a.fetch(0).my_type.type_string, relay.arglist.to_a.fetch(0).my_type.type_string]).to eq(
        [type_name, type_name]
      )
      expect(sink.blocks[0].all_nodes(DabNodeReturn).fetch(0).value).to be_a(DabNodeLocalVar)
      expect(relay.blocks[0].all_nodes(DabNodeCall).fetch(0).args.fetch(0)).to be_a(DabNodeLocalVar)
      expect(relay.blocks[0].all_nodes(DabNodeReturn).fetch(0).value).to be_a(DabNodeLocalVar)
    end
  end

  it 'accepts only the existing reference-bearing call, print, puts, producer, and return slots' do
    source = <<~DAB
      def producer(value:String):String
      return value
      end
      def sink(value:String)
      end
      def relay(value:String):String
      sink(value)
      print(value)
      puts(value)
      sink(producer(value))
      return value
      end
    DAB
    unit = DabNodeUnit.new
    unit.add_function(puts_stub)
    relay = lower(source, unit).fetch(2)

    expect(relay.blocks[0].all_nodes(DabNodeCall).map(&:real_identifier)).to eq(
      %w[sink print puts sink producer]
    )
    expect(relay.blocks[0].all_nodes(DabNodeLocalVar).map(&:real_identifier)).to eq(
      Array.new(5, 'value')
    )
    expect(relay.blocks[0].all_nodes(DabNodeReturn).fetch(0).value).to be_a(DabNodeLocalVar)
  end

  it 'retains parameter order and resolves repeated reads to stable typed entry definitions' do
    source = <<~DAB
      def relay(first:String,second:Int32):String
      print(first)
      print(first)
      return first
      end
    DAB
    function = lower(source)
    function.extremely_early_init!
    definitions = function.blocks[0].all_nodes(DabNodeDefineLocalVar)
    references = function.blocks[0].all_nodes(DabNodeLocalVar)

    expect(function.arglist.map { |argument| [argument.index, argument.identifier, argument.my_type.type_string] }).to eq(
      [[0, 'first', 'String'], [1, 'second', 'Int32']]
    )
    expect(definitions.map(&:real_identifier)).to eq(%w[first second])
    expect(definitions.map { |definition| definition.my_type.type_string }).to eq(%w[String Int32])
    expect(references.map(&:real_identifier)).to eq(%w[first first first])
    expect(references.map(&:last_var_setter).uniq).to eq([definitions.fetch(0)])
  end

  it 'accepts exact String interpolation and lowers every splice as the same entry reference' do
    source = <<~DAB
      def relay(value:String):String
      print("\#{value}:\#{value}")
      return "\#{value}"
      end
    DAB
    function = lower(source)
    interpolations = function.blocks[0].all_nodes(DabNodeModernInterpolatedString)

    expect(interpolations.length).to eq(2)
    expect(interpolations.flat_map { |node| node.all_nodes(DabNodeLocalVar) }.map(&:real_identifier)).to eq(
      %w[value value value]
    )
    expect(interpolations.flat_map { |node| node.all_nodes(DabNodeInstanceCall) }).to be_empty
  end

  it 'rejects every non-String parameter interpolation with its exact type and identifier span' do
    non_string_types = DabModernBootstrapParser::SUPPORTED_TYPE_NAMES - ['String']
    non_string_types.each do |type_name|
      source = "def relay(value:#{type_name})\nprint(\"\#{value}\")\nend\n"
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(
          "cannot interpolate Modern parameter \"value\" of type #{type_name}; " \
          'simple interpolation requires exact String'
        )
        start = source.index('value', source.index('#{'))
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([start, start + 5])
      }
    end
  end

  it 'keeps call and return mismatch policies and full-reference diagnostics unchanged' do
    call_mismatch = <<~DAB
      def sink(value:String)
      end
      def relay(actual:Fixnum)
      sink(actual)
      end
    DAB
    expect do
      lower(call_mismatch)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "sink"'
      )
      start = call_mismatch.rindex('actual')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([start, start + 6])
    }

    return_mismatch = "def relay(actual:Fixnum):String\nreturn actual\nend\n"
    expect do
      lower(return_mismatch)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot return Modern value of type Fixnum from function "relay" with declared return type String'
      )
      start = return_mismatch.rindex('actual')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([start, start + 6])
    }
  end

  it 'keeps parameters function-local while permitting same-name parameters in separate functions' do
    reuse = <<~DAB
      def first(value:String):String
      return value
      end
      def second(value:String):String
      return value
      end
    DAB
    expect(lower(reuse).map(&:identifier)).to eq(%w[first second])

    cross_function = <<~DAB
      def first(value:String)
      end
      def second():String
      return value
      end
    DAB
    expect_generic_error(cross_function, 'value', occurrence: :last)
  end

  it 'validates accepted references and unknown identifiers throughout unreachable tails' do
    accepted = <<~DAB
      def relay(value:String):String
      return value
      print(value)
      end
    DAB
    expect { lower(accepted) }.not_to raise_error

    unknown = <<~DAB
      def relay(value:String):String
      return value
      print(missing)
      end
    DAB
    expect_generic_error(unknown, 'missing')
  end

  it 'preserves arity precedence, left-to-right argument checks, and zero partial publication' do
    arity = <<~DAB
      def sink(first:String,second:String)
      end
      def relay(value:Fixnum)
      sink(value)
      end
    DAB
    expect do
      lower(arity)
    end.to raise_error(
      DabModernBootstrapParseError,
      'incorrect Modern call arity for "sink": got 1, expected 2'
    )

    left_to_right = <<~DAB
      def sink(first:String,second:String)
      end
      def relay(first:Fixnum,second:Fixnum)
      sink(first,second)
      end
    DAB
    expect do
      lower(left_to_right)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to start_with('cannot pass Modern argument of type Fixnum to parameter "first"')
      start = left_to_right.index('first', left_to_right.rindex('sink(first'))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([start, start + 5])
    }

    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    transactional = <<~DAB
      def relay(value:String):String
      return value
      end
      def main()
      missing()
      end
    DAB
    expect { lower(transactional, unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'parses the complete document before source-ordered parameter preflight' do
    source = <<~DAB
      def relay(value:Int32)
      print("\#{value}")
      print(,)
      end
    DAB
    expect { parse(source) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )
  end

  it 'keeps every excluded parameter slot and expression form closed' do
    cases = {
      'standalone body item' => ["def relay(value:String)\nvalue\nend\n", 'value'],
      'let initializer' => ["def relay(value:String)\nlet copy = value\nend\n", 'value'],
      'var initializer' => ["def relay(value:String)\nvar copy = value\nend\n", 'value'],
      'local write RHS' => ["def relay(value:String)\nvar copy = \"x\"\ncopy = value\nend\n", 'value'],
      'parameter assignment' => ["def relay(value:String)\nvalue = \"x\"\nend\n", 'value'],
      'parameter default' => ["def relay(value:String=\"x\")\nend\n", '='],
      'member receiver' => ["def relay(value:String)\nvalue.length\nend\n", 'value'],
      'member argument' => ["def relay(value:String)\nprint(\"x\".length(value))\nend\n", 'value'],
      'member chaining' => ["def relay(value:String)\nprint(value.length.to_s)\nend\n", 'value'],
      'parentheses' => ["def relay(value:String)\nprint((value))\nend\n", '('],
      'operator' => ["def relay(value:String)\nprint(value+\"x\")\nend\n", '+'],
      'block' => ["def relay(value:String)\nprint(value) do\nend\nend\n", 'do'],
      'closure' => ["def relay(value:String)\nprint({ value })\nend\n", '{'],
      'capture' => ["def relay(value:String)\nprint(&value)\nend\n", '&'],
      'deeper producer nesting' => [
        "def wrap(value:String):String\nreturn value\nend\n" \
        "def sink(value:String)\nend\n" \
        "def relay(value:String)\nsink(wrap(wrap(value)))\nend\n",
        'wrap',
      ],
    }

    cases.each do |description, (source, offending)|
      expect { lower(source) }.to raise_error(DabModernBootstrapParseError), description
      expect(source).to include(offending), description
    end

    call_target = "def relay(value:String)\nvalue()\nend\n"
    expect { lower(call_target) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "value"'
    )
  end

  it 'locks fixtures 0092 and 0093 as the primary runtime and diagnostic evidence' do
    success = DabModernSourceFixture.load(
      File.join(root, 'test/modern_source/0092_parameter_references.dabmtest')
    )
    rejection = DabModernSourceFixture.load(
      File.join(root, 'test/modern_source/0093_non_string_parameter_interpolation.dabmtest')
    )

    expect([success.expected_status, success.expected_application_stdout]).to eq(
      [0, "VV\nVV\nPPP:V\nV"]
    )
    echo_assembly = success.expected_stdout.match(/Fecho:.*?__Fecho_END:/m).to_s
    emit_assembly = success.expected_stdout.match(/Femit:.*?__Femit_END:/m).to_s
    relay_assembly = success.expected_stdout.match(/Frelay:.*?__Frelay_END:/m).to_s
    expect(echo_assembly).to include('LOAD_ARG R0, 0', 'RETURN R0')
    expect(emit_assembly).to include('LOAD_ARG R0, 0', 'SYSCALL RNIL, 0, R0', 'CALL RNIL, S40, R0')
    expect(relay_assembly).to include(
      'LOAD_ARG R0, 0',
      'LOAD_ARG R1, 1',
      'CALL RNIL, S55, R1',
      'CALL R2, S54, R1',
      'SYSCALL RNIL, 0, R0',
      'INSTCALL R4, R0, S2, R3',
      'INSTCALL R5, R4, S2, R1',
      'RETURN R1'
    )
    expect(relay_assembly.scan('SYSCALL RNIL, 0, R0').length).to eq(2)
    expect(rejection.expected_status).to eq(2)
    expect(rejection.expected_stdout).to eq('')
    expect(rejection.expected_stderr).to eq(
      'compiler: 0093_non_string_parameter_interpolation.dabm:2:11: error: ' \
      'cannot interpolate Modern parameter "value" of type Int32; ' \
      "simple interpolation requires exact String\n"
    )
  end
end
