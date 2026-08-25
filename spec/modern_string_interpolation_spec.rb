require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern String interpolation' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
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

  def optimize_interpolations(source)
    lowered = parse(source).lower_into(DabNodeUnit.new)
    functions = lowered.is_a?(Array) ? lowered : [lowered]
    functions.each { |function| SSAify.new.run(function) }
    100.times do
      changed = functions.map(&:run_optimize_processors!).any?
      return functions unless changed
    end
    raise 'Modern interpolation optimization did not converge after 100 passes'
  end

  def invoke(*command, input: nil, binmode: false)
    options = {stdin_data: input, chdir: root}
    options[:binmode] = true if binmode
    Open3.capture3(*command, **options)
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
    expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq([0, "PASS #{artifact}\n", ''])
    artifact
  end

  def compile_source(directory, basename, extension, source, rings: [])
    path = File.join(directory, "#{basename}.#{extension}")
    File.binwrite(path, source)
    arguments = [RbConfig.ruby, compiler, path, *rings.map { |ring| "--ring-base[]=#{ring}" }]
    assembly, stderr, status = invoke(*arguments)
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    assembly
  end

  def assemble(directory, basename, assembly)
    artifact, stderr, status = invoke(
      RbConfig.ruby,
      '-e',
      'STDOUT.binmode; load ARGV.shift',
      assembler,
      input: assembly,
      binmode: true
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    path = File.join(directory, "#{basename}.dabcb")
    File.binwrite(path, artifact)
    path
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

  it 'retains exact wrapper, splice, padding, and expression spans for bounded expression splices' do
    source = "\"\#{  producer(\"}\") }/\#{value}/\#{ \"literal\"}\""
    value = interpolation(source)
    first, second, third = value.splices

    expect(value.source_span.source_unit).to equal(source_unit)
    expect([value.source_span.start_offset, value.source_span.end_offset]).to eq([0, source.bytesize])
    expect(first.expression).to be_a(DabModernBootstrapDirectCall)
    expect(second.expression).to be_a(DabModernBootstrapLocalReference)
    expect(third.expression).to be_a(DabModernBootstrapToken)
    expect(third.expression.kind).to eq(:string)
    expect(value.splices).to all(satisfy { |splice| splice.source_span.source_unit.equal?(source_unit) })
    expect(value.splices.map { |splice| [splice.source_span.start_offset, splice.source_span.end_offset] }).to eq(
      [[1, 20], [21, 29], [30, 43]]
    )
    expect(value.splices.map do |splice|
      [splice.expression.source_span.start_offset,
       splice.expression.source_span.end_offset]
    end).to eq(
      [[5, 18], [23, 28], [33, 42]]
    )
    expect(first.leading_padding_tokens.map(&:text)).to eq([' ', ' '])
    expect(first.trailing_padding_tokens.map(&:text)).to eq([' '])
    expect(value.source_tokens.map(&:text).join).to eq(source)
  end

  it 'accepts bounded exact-String literal, reference, member-free call, and mixed repeated splices' do
    source = <<~'DAB'
      def producer(value:String):String
      return value
      end
      def main(parameter:String)
      let local = "local"
      print("#{ "literal" }#{local}:#{producer(parameter)}:#{local}")
      end
    DAB
    document = parse(source)
    functions = document.lower_into(DabNodeUnit.new)
    main = functions.fetch(1)
    wrapper = main.all_nodes(DabNodeModernInterpolatedString).fetch(0)

    expect(wrapper.my_type.type_string).to eq('String')
    expect(wrapper.all_nodes(DabNodeCall).map(&:real_identifier)).to eq(['producer'])
    expect(wrapper.all_nodes(DabNodeLocalVar).map(&:real_identifier)).to eq(%w[local parameter local])
    expect(wrapper.all_nodes(DabNodeInstanceCall).map { |call| call.identifier.to_s }).to all(eq('+'))
  end

  it 'accepts all four ASCII SPACE boundary combinations and preserves direct-call horizontal whitespace' do
    source = <<~'DAB'
      def producer(value:String):String
      return value
      end
      def main()
      print("#{producer("zero")}#{ producer("leading")}#{producer("trailing") }#{ producer 	 ( "both" ) }")
      end
    DAB
    document = parse(source)
    main = document.lower_into(DabNodeUnit.new).fetch(1)
    splices = document.declarations.fetch(1).body_items.fetch(0).arguments.fetch(0).value.splices

    expect(splices.map do |splice|
      [splice.leading_padding_tokens.length,
       splice.trailing_padding_tokens.length]
    end).to eq(
      [[0, 0], [1, 0], [0, 1], [1, 1]]
    )
    expect(main.all_nodes(DabNodeCall).map(&:real_identifier)).to eq(%w[print producer producer producer producer])
  end

  it 'lets nested ordinary String and Regex tokens own internal braces and escaped openers' do
    source = <<~'DAB'
      def text(value:String):String
      return value
      end
      def main()
      print("#{text("}")}:#{text("\#{escaped}")}")
      end
    DAB
    document = parse(source)
    main = document.lower_into(DabNodeUnit.new).fetch(1)
    regex = interpolation("\"\#{ /a}b/ }\"").splices.fetch(0).expression

    expect(main.all_nodes(DabNodeCall).map(&:real_identifier)).to eq(%w[print text text])
    expect(document.declarations.fetch(1).body_items.fetch(0).arguments.fetch(0).value.splices.length).to eq(2)
    expect([regex.kind, regex.value.body.text]).to eq([:regex_literal, 'a}b'])
  end

  it 'rejects TAB, comments, LF, CR, and CRLF as splice boundary padding' do
    cases = {
      "\"\#{\tvalue}\"".b => [3, 4],
      "\"\#{value\t}\"".b => [8, 9],
      "\"\#{#comment}\"".b => [3, 13],
      "\"\#{value#comment}\"".b => [8, 18],
      "\"\#{\nvalue}\"".b => [3, 4],
      "\"\#{value\r}\"".b => [8, 9],
      "\"\#{value\r\n}\"".b => [8, 10],
    }

    cases.each do |source, span|
      token = scan(source)
      expect(token.kind).to eq(:unsupported), source.inspect
      expect([token.source_span.start_offset, token.source_span.end_offset]).to eq(span), source.inspect
    end
  end

  it 'rejects nesting, call-result arguments, grouping, operators, unary negatives, receivers, and chains' do
    cases = {
      "\"\#{ \"\#{value}\" }\"" => "\#{value}",
      "\"\#{outer(\"\#{value}\")}\"" => "\#{value}",
      "\"\#{outer(inner())}\"" => 'inner',
      "\"\#{(value)}\"" => '(',
      "\"\#{value + value}\"" => '+',
      "\"\#{-1}\"" => '-',
      "\"\#{value.call()}\"" => '.',
      "\"\#{producer().length}\"" => '.',
    }

    cases.each do |source, marker|
      token = scan(source.b)
      expect(token.kind).to eq(:unsupported), source
      start_offset = source.index(marker)
      expect(token.source_span.start_offset).to eq(start_offset), source
    end
    nested = scan("\"\#{ \"\#{value}\" }\"")
    expect(nested.diagnostic_message).to eq('nested Modern String interpolation is not supported until EX-012')
  end

  it 'rejects every supported non-String expression on its complete unpadded expression span' do
    cases = {
      'nil' => 'NilClass',
      'true' => 'Boolean',
      '1' => 'Fixnum',
      '/x}/' => 'Regex',
      '"abc".length' => 'Int32',
    }

    cases.each do |expression, actual|
      source = "def main()\nprint(\"\#{  #{expression} }\")\nend\n"
      expect { parse(source).lower_into(DabNodeUnit.new) }.to raise_error(
        DabModernBootstrapParseError,
        "cannot interpolate Modern expression of type #{actual}; EX-011 requires exact String"
      ) { |error|
        start_offset = source.index(expression)
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [start_offset, start_offset + expression.bytesize]
        )
      }, expression
    end
  end

  it 'rejects non-String local, parameter, call-result, and absent-result expressions uniformly' do
    cases = [
      ["def main(value:Int32)\nprint(\"\#{ value }\")\nend\n", 'value', 'Int32'],
      ["def main()\nlet value = /x/\nprint(\"\#{value}\")\nend\n", 'value', 'Regex'],
      ["def value():Boolean\nreturn true\nend\ndef main()\nprint(\"\#{ value() }\")\nend\n", 'value()', 'Boolean'],
      ["def value()\nend\ndef main()\nprint(\"\#{value()}\")\nend\n", 'value()', 'Object'],
    ]

    cases.each do |source, expression, actual|
      expect { parse(source).lower_into(DabNodeUnit.new) }.to raise_error(
        DabModernBootstrapParseError,
        "cannot interpolate Modern expression of type #{actual}; EX-011 requires exact String"
      ) { |error|
        start_offset = source.index(expression, source.index('#{'))
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [start_offset, start_offset + expression.bytesize]
        )
      }
    end
  end

  it 'preserves target, arity, argument, and member validation before the EX-011 result check' do
    cases = {
      <<~'DAB' => 'unknown Modern call target "missing"',
        def main()
        print("#{missing()}")
        end
      DAB
      <<~'DAB' => 'incorrect Modern call arity for "producer": got 0, expected 1',
        def producer(value:String):String
        return value
        end
        def main()
        print("#{producer()}")
        end
      DAB
      <<~'DAB' => 'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "producer"',
        def producer(value:String):String
        return value
        end
        def main()
        print("#{producer(1)}")
        end
      DAB
      <<~'DAB' => 'unknown Modern member target "String#missing"',
        def main()
        print("#{"value".missing}")
        end
      DAB
    }

    cases.each do |source, message|
      expect { parse(source).lower_into(DabNodeUnit.new) }
        .to raise_error(DabModernBootstrapParseError, message)
    end
  end

  it 'preflights invalid expression calls in dead branches without partially publishing functions' do
    source = <<~'DAB'
      def valid():String
      return "valid"
      end
      def invalid():String
      if false
      return "#{missing()}"
      end
      return "unselected"
      end
    DAB
    document = parse(source)
    unit = DabNodeUnit.new

    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to be_empty
  end

  it 'retains malformed nested String, UTF-8, NUL, escape, and newline precedence' do
    invalid_utf8 = "\"\#{ \"".b + [0xFF].pack('C') + '" }"'.b
    invalid_boundary_utf8 = "\"\#{value".b + [0xFF].pack('C') + '}"'.b
    nul = "\"\#{ \"a\0b\" }\"".b
    cases = {
      "\"\#{ \"\\q\" }\"".b => 'invalid Modern String literal escape',
      invalid_utf8 => 'invalid UTF-8 byte 0xFF in Modern String literal',
      invalid_boundary_utf8 => 'invalid UTF-8 byte 0xFF in Modern String literal',
      nul => 'invalid Modern String literal: NUL is not allowed',
      "\"\#{value\0}\"".b => 'invalid Modern String literal: NUL is not allowed',
      "\"\#{ \"a\nb\" }\"".b => 'invalid Modern String literal: literal LF is not allowed',
      "\"\#{ \"a\rb\" }\"".b => 'invalid Modern String literal: literal CR is not allowed',
    }

    cases.each do |source, message|
      token = scan(source)
      expect(token.kind).to eq(:unsupported), source.inspect
      expect(token.diagnostic_message).to include(message), source.inspect
    end
  end

  it 'keeps escaped openers literal, honors backslash parity, and never rescans decoded escapes' do
    literal = scan('"literal \\#{name} and \\u0023{name}"')
    even = scan('"\\\\#{name}"')
    odd = scan('"\\\\\\#{name}"')

    expect([literal.kind, literal.value]).to eq([:string, "literal \#{name} and \#{name}".b])
    expect([even.kind, even.value.splices.map(&:name)]).to eq([:interpolated_string, ['name']])
    expect([odd.kind, odd.value]).to eq([:string, '\\#{name}'.b])
  end

  it 'emits the exact expression closer diagnostic with extra-token and EOF spans' do
    cases = {
      "\"\#{}\"" => [
        'invalid Modern String interpolation: expected "}" after expression',
        3,
        4,
      ],
      "\"\#{ }\"" => [
        'invalid Modern String interpolation: expected "}" after expression',
        4,
        5,
      ],
      "\"\#{name  extra}\"" => [
        'invalid Modern String interpolation: expected "}" after expression',
        9,
        14,
      ],
      '"#{name' => [
        'invalid Modern String interpolation: expected "}" after expression',
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

  it 'accepts an exact-String local or parameter and rejects every other binding flow' do
    accepted = <<~DAB
      def main()
      let fixed = "fixed"
      var flowed = nil
      flowed = "flowed"
      print("\#{fixed}:\#{flowed}")
      end
    DAB
    expect { parse(accepted) }.not_to raise_error
    expect { parse("def main(value:String)\nprint(\"\#{value}\")\nend\n") }.not_to raise_error

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
      non_string_parameter: [
        "def main(value:Int32)\nprint(\"\#{value}\")\nend\n",
        'cannot interpolate Modern expression of type Int32; EX-011 requires exact String',
        'value',
      ],
      non_string: [
        "def main()\nvar value = \"first\"\nvalue = 1\nprint(\"\#{value}\")\nend\n",
        'cannot interpolate Modern expression of type Fixnum; EX-011 requires exact String',
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

  it 'folds literal, latest-write, self-read, chained, repeated, and adjacent provenance as one append' do
    source = <<~'DAB'
      def main()
      let fixed = "A"
      var latest = "old"
      latest = "B"
      latest = "#{fixed}#{latest}"
      let chained = "<#{latest}>"
      print("#{chained}:#{fixed}#{fixed}")
      end
    DAB
    main = optimize_interpolations(source).fetch(0)
    wrappers = main.all_nodes(DabNodeModernInterpolatedString)

    expect(wrappers.map { |wrapper| wrapper.formatted_source(syntax_profile: DabSyntaxProfile::MODERN) }).to eq(
      [
        "\"\#{fixed}\#{latest}\"",
        "\"<\#{latest}>\"",
        "\"\#{chained}:\#{fixed}\#{fixed}\"",
      ]
    )
    expect(wrappers.map { |wrapper| wrapper.all_nodes(DabNodeModernStringAppend).length }).to eq([1, 1, 1])
    expect(
      wrappers.map { |wrapper| wrapper.all_nodes(DabNodeLiteralString).map(&:constant_value) }
    ).to eq(
      [['', 'AB'], ['', '<AB>'], ['', '<AB>:AA']]
    )
    expect(wrappers).to all(satisfy { |wrapper| wrapper.all_nodes(DabNodeSSAGet).empty? })
  end

  it 'concatenates decoded escapes and UTF-8 bytes once without rescanning them' do
    source = <<~'DAB'
      def main()
      let value = "\u{17B}\n\#{literal}"
      print("<#{value}>\t#{value}")
      end
    DAB
    main = optimize_interpolations(source).fetch(0)
    wrapper = main.all_nodes(DabNodeModernInterpolatedString).fetch(0)

    expect(wrapper.all_nodes(DabNodeModernStringAppend).length).to eq(1)
    expect(wrapper.all_nodes(DabNodeLiteralString).map(&:constant_value)).to eq(
      ['', "<Ż\n\#{literal}>\tŻ\n\#{literal}".b]
    )
  end

  it 'vetoes a whole composed wrapper on parameter provenance and leaves its tree unchanged' do
    source = <<~'DAB'
      def greet(name:String)
      let fixed = "fixed"
      print("#{fixed}:#{name}:#{fixed}")
      end
    DAB
    greet = optimize_interpolations(source).fetch(0)
    wrapper = greet.all_nodes(DabNodeModernInterpolatedString).fetch(0)

    expect(wrapper.all_nodes(DabNodeModernStringAppend).length).to eq(4)
    expect(wrapper.all_nodes(DabNodeLocalVar).map(&:real_identifier)).to include('name')
    expect(wrapper.all_nodes(DabNodeLiteralString).map(&:constant_value)).to eq([':', ':'])
  end

  it 'preserves lone-splice identity and the original wrapper source ownership' do
    source = <<~'DAB'
      def main()
      let value = "identity"
      print("#{value}")
      end
    DAB
    main = optimize_interpolations(source).fetch(0)
    wrapper = main.all_nodes(DabNodeModernInterpolatedString).fetch(0)

    expect(wrapper.value).to be_a(DabNodeSSAGet)
    expect(wrapper.all_nodes(DabNodeModernStringAppend)).to be_empty
    expect(wrapper.source_parts.map(&:to_s).join).to eq("\"\#{value}\"")
  end

  it 'retains complete source ownership while synthetic folded children have none' do
    source = <<~'DAB'
      def main()
      let value = "value"
      print("left #{value} right")
      end
    DAB
    main = optimize_interpolations(source).fetch(0)
    wrapper = main.all_nodes(DabNodeModernInterpolatedString).fetch(0)
    literals = wrapper.all_nodes(DabNodeLiteralString)

    expect(wrapper.source_parts.map(&:to_s).join).to eq("\"left \#{value} right\"")
    expect(literals.map(&:source_parts)).to eq([[], []])
  end

  it 'keeps a standalone folded append call-like during unused-value stripping' do
    source = <<~'DAB'
      def main()
      let value = "value"
      "left #{value} right"
      end
    DAB
    main = optimize_interpolations(source).fetch(0)
    wrapper = main.all_nodes(DabNodeModernInterpolatedString).fetch(0)
    block = wrapper.parent

    expect(wrapper.all_nodes(DabNodeModernStringAppend).length).to eq(1)
    expect(wrapper.no_side_effects?).to be(false)
    StripUnusedValues.new.run(block)
    expect(block.all_nodes(DabNodeModernInterpolatedString)).to contain_exactly(wrapper)
  end

  it 'checks the real folded byte limit and fails closed above it' do
    wrapper = DabNodeModernInterpolatedString.new(
      [DabNodeLiteralString.new('a'), DabNodeLiteralString.new('b')],
      source: '"ab"',
      consumed: true
    )
    maximum = DabNodeModernInterpolatedString::MAX_FOLDED_BYTES

    expect(wrapper.send(:static_concat_in_range?, 0, maximum)).to be(true)
    expect(wrapper.send(:static_concat_in_range?, maximum - 1, 1)).to be(true)
    expect(wrapper.send(:static_concat_in_range?, maximum, 0)).to be(true)
    expect(wrapper.send(:static_concat_in_range?, maximum, 1)).to be(false)
    expect(wrapper.send(:static_concat_in_range?, maximum + 1, 0)).to be(false)
  end

  it 'retains composed DynamicString representation and lone-splice identity across Rings', :native do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-static-interpolation-classes') do |directory|
      lower = build_stdlib(directory)
      modern_assembly = compile_source(
        directory,
        'providers',
        'dabm',
        <<~'DAB',
          def composed_value():String
          let value = "AB"
          return "<#{value}>"
          end

          def lone_value():String
          let value = "AB"
          return "#{value}"
          end
        DAB
        rings: [lower]
      )
      providers = assemble(directory, 'providers', modern_assembly)
      legacy_assembly = compile_source(
        directory,
        'consumer',
        'dab',
        <<~DAB,
          func legacy_main()
          {
            var composed = composed_value();
            var lone = lone_value();
            print(composed.class);
            print("|");
            print(lone.class);
          }
        DAB
        rings: [lower, providers]
      )
      consumer = assemble(directory, 'consumer', legacy_assembly)
      application_output = File.join(directory, 'application.stdout')
      stdout, stderr, status = invoke(
        vm,
        '--entry=legacy_main',
        "--out=#{application_output}",
        lower,
        providers,
        consumer
      )

      expect([status.exitstatus, stdout]).to eq([0, ''])
      expect(stderr).not_to include('ERROR', 'exception:', 'FAILED')
      expect(File.binread(application_output)).to eq('DynamicString|LiteralString'.b)
    end
  end
end
