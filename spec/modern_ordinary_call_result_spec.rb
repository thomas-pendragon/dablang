require 'spec_helper'

require 'digest'
require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern one-level ordinary-call results' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:source_unit) do
    DabSourceUnit.new(input: 'ordinary-call-result.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
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

  def expect_lower_error(source, message, expression, occurrence: :first, unit: DabNodeUnit.new)
    expect { lower(source, unit) }.to raise_error(DabModernBootstrapParseError) { |error|
      start = occurrence == :last ? source.rindex(expression) : source.index(expression)
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + expression.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  def puts_stub
    DabNodeFunctionStub.new('puts', nil, is_static: false, ring_signature: puts_signature)
  end

  def invoke(*command, input: nil, binmode: false)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-call-result-bundler')}
    Open3.capture3(environment, *command, stdin_data: input, binmode: binmode, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq([0, "PASS #{artifact}\n"])
    expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')
    artifact
  end

  def compile_source(source, directory, lower_ring, basename)
    path = File.join(directory, "#{basename}.dabm")
    File.binwrite(path, source)
    stdout, stderr, status = invoke(RbConfig.ruby, compiler, path, "--ring-base[]=#{lower_ring}")
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    stdout
  end

  it 'builds immutable direct-call values for complete returns and one outer argument' do
    source = <<~DAB
      def producer():String
      return "value"
      end
      def sink(value:String)
      end
      def main():String
      sink(producer())
      return producer()
      end
    DAB
    document = parse(source)
    sink_call, value_return = document.declarations.fetch(2).body_items
    argument_call = sink_call.arguments.fetch(0)

    expect(argument_call).to be_a(DabModernBootstrapDirectCall)
    expect(value_return.value).to be_a(DabModernBootstrapDirectCall)
    expect(argument_call).to be_frozen
    expect(argument_call.source_tokens).to be_frozen
    expect(source.byteslice(argument_call.source_span.start_offset...argument_call.source_span.end_offset)).to eq(
      'producer()'
    )

    main = document.lower_into(DabNodeUnit.new).fetch(2)
    expect(main.blocks[0].all_nodes(DabNodeCall).map(&:real_identifier)).to eq(%w[sink producer producer])
    expect(main.blocks[0].all_nodes(DabNodeReturn).fetch(0).value).to be_a(DabNodeCall)
  end

  it 'uses only exact producer metadata or an omitted Object consumer without conversion' do
    exact = <<~DAB
      def producer():String
      return "value"
      end
      def sink(value:String)
      end
      def main():String
      sink(producer())
      return producer()
      end
    DAB
    expect { lower(exact) }.not_to raise_error

    object_consumer = <<~DAB
      def producer():String
      return "value"
      end
      def main()
      return producer()
      end
    DAB
    expect { lower(object_consumer) }.not_to raise_error

    omitted_producer = <<~DAB
      def producer()
      return "value"
      end
      def main():String
      return producer()
      end
    DAB
    expect_lower_error(
      omitted_producer,
      'cannot return Modern value of type Object from function "main" with declared return type String',
      'producer()',
      occurrence: :last
    )

    broad_assignability = <<~DAB
      def producer():IntPtr
      return nil
      end
      def main():String
      return producer()
      end
    DAB
    expect(DabType.parse('String').can_assign_from?(DabType.parse('IntPtr'))).to be(true)
    expect_lower_error(
      broad_assignability,
      'cannot return Modern value of type IntPtr from function "main" with declared return type String',
      'producer()',
      occurrence: :last
    )
  end

  it 'rejects omitted Object metadata in a concrete ordinary-call slot at the full inner call' do
    source = <<~DAB
      def producer()
      return "value"
      end
      def sink(value:String)
      end
      def main()
      sink(producer())
      end
    DAB
    expect_lower_error(
      source,
      'cannot pass Modern argument of type Object to parameter "value" of type String in call "sink"',
      'producer()',
      occurrence: :last
    )
  end

  it 'trusts declared metadata without return-path completeness analysis' do
    source = <<~DAB
      def bare():String
      return
      end
      def fallthrough():String
      end
      def main():String
      print(bare())
      return fallthrough()
      end
    DAB
    expect { lower(source) }.not_to raise_error
  end

  it 'validates the outer target and arity before inner producers' do
    unknown_outer = <<~DAB
      def main()
      missing(inner())
      end
    DAB
    expect_lower_error(unknown_outer, 'unknown Modern call target "missing"', 'missing')

    arity_outer = <<~DAB
      def sink()
      end
      def main()
      sink(inner())
      end
    DAB
    expect_lower_error(
      arity_outer,
      'incorrect Modern call arity for "sink": got 1, expected 0',
      'sink(inner())'
    )
  end

  it 'validates inner target, arity, arguments, and result type in that order' do
    unknown = <<~DAB
      def sink(value:String)
      end
      def main()
      sink(missing())
      end
    DAB
    expect_lower_error(unknown, 'unknown Modern call target "missing"', 'missing')

    arity = <<~DAB
      def producer(value:String):String
      return "value"
      end
      def sink(value:String)
      end
      def main()
      sink(producer())
      end
    DAB
    expect_lower_error(
      arity,
      'incorrect Modern call arity for "producer": got 0, expected 1',
      'producer()',
      occurrence: :last
    )

    argument = <<~DAB
      def producer(value:String):String
      return "value"
      end
      def sink(value:String)
      end
      def main()
      sink(producer(1))
      end
    DAB
    expect_lower_error(
      argument,
      'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "producer"',
      '1'
    )
  end

  it 'checks call-result arguments from left to right' do
    source = <<~DAB
      def sink(first:String,second:String)
      end
      def second():String
      return "second"
      end
      def main()
      sink(first(),second())
      end
    DAB
    expect_lower_error(source, 'unknown Modern call target "first"', 'first', occurrence: :last)
  end

  it 'allows unary print and approved unary puts as Object consumers' do
    source = <<~DAB
      def producer():String
      return "value"
      end
      def main()
      print(producer())
      puts(producer())
      end
    DAB
    unit = DabNodeUnit.new
    unit.add_function(puts_stub)
    functions = lower(source, unit)
    main = functions.fetch(1)

    expect(main.blocks[0].all_nodes(DabNodeCall).map(&:real_identifier)).to eq(
      %w[print producer puts producer]
    )
  end

  it 'preserves approved producer literal, local, and member-result arguments' do
    source = <<~DAB
      def producer(first:String,second:String,count:Int32):String
      return "result"
      end
      def main():String
      let fixed = "fixed"
      return producer("literal",fixed,"abc".length)
      end
    DAB
    expect { lower(source) }.not_to raise_error
  end

  it 'admits a parameter leaf while keeping deeper calls and broader expression forms excluded' do
    parameter = "def producer(value:String):String\nreturn value\nend\n" \
                "def main(value:String):String\nreturn producer(value)\nend\n"
    expect { lower(parameter) }.not_to raise_error

    cases = {
      'deeper call' => "def nested():String\nreturn \"n\"\nend\ndef producer(value:String):String\nreturn value\nend\ndef sink(value:String)\nend\ndef main()\nsink(producer(nested()))\nend\n",
      'binding' => "def producer():String\nreturn \"x\"\nend\ndef main()\nlet value = producer()\nend\n",
      'member receiver' => "def producer():String\nreturn \"x\"\nend\ndef main():String\nreturn producer().length\nend\n",
      'operator' => "def producer():Fixnum\nreturn 1\nend\ndef main():Fixnum\nreturn producer()+1\nend\n",
      'parentheses' => "def producer():String\nreturn \"x\"\nend\ndef main():String\nreturn (producer())\nend\n",
    }

    cases.each do |description, source|
      expect { lower(source) }.to raise_error(DabModernBootstrapParseError), description
    end
  end

  it 'retains direct and mutual recursion without termination analysis' do
    source = <<~DAB
      def direct():String
      return direct()
      end
      def left():String
      return right()
      end
      def right():String
      return left()
      end
      def main():String
      return direct()
      end
    DAB
    expect { lower(source) }.not_to raise_error
  end

  it 'preflights complete unreachable tails and publishes no partial unit' do
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    source = <<~DAB
      def producer():String
      return "value"
      end
      def main():String
      return producer()
      missing()
      end
    DAB

    expect { lower(source, unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'emits standalone RNIL and consumed CALL registers deterministically without conversion' do
    source = <<~DAB
      def producer():String
      print("producer\\n")
      return "value"
      end
      def sink(first:String,value:String,last:String)
      print("sink\\n")
      end
      def main():String
      producer()
      sink("left\\n",producer(),"right\\n")
      return producer()
      end
    DAB

    Dir.mktmpdir('dab-modern-call-result') do |directory|
      lower_ring = build_stdlib(directory)
      assemblies = 2.times.map do |index|
        compile_source(source, directory, lower_ring, "call-result-#{index}")
      end
      artifacts = assemblies.map do |assembly|
        artifact, stderr, status = invoke(
          RbConfig.ruby,
          '-e',
          'STDOUT.binmode; load ARGV.shift',
          assembler,
          input: assembly,
          binmode: true
        )
        expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
        artifact
      end

      expect(assemblies.uniq.length).to eq(1)
      expect(artifacts.uniq.length).to eq(1)
      expect(Digest::SHA256.hexdigest(artifacts.fetch(0))).to match(/\A[0-9a-f]{64}\z/)

      main = assemblies.fetch(0).match(/Fmain:.*?__Fmain_END:/m).to_s
      producer_destinations = main.scan(%r{/\* producer\s+\*/\s+CALL (RNIL|R\d+), S\d+}).flatten
      expect(producer_destinations.fetch(0)).to eq('RNIL')
      expect(producer_destinations.drop(1)).to all(match(/\AR\d+\z/))
      expect(producer_destinations.length).to eq(3)
      expect(main).to match(%r{/\* producer\s+\*/\s+CALL (R\d+), S\d+\n\s+RETURN \1})
      expect(main).to match(%r{LOAD_STRING R\d+.*?/\* producer\s+\*/\s+CALL R\d+.*?LOAD_STRING R\d+.*?/\* sink\s+\*/\s+CALL RNIL}m)
      expect(main).not_to include('CAST')
    end
  end
end
