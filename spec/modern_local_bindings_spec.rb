require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern fixed local bindings' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'local-bindings.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def invoke(*command)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-bundler')}
    Open3.capture3(environment, *command, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  it 'retains immutable literal bindings, local references, source text, and exact spans' do
    source = <<~DAB
      def consume(a:NilClass,b:Boolean,c:Fixnum,d:String)
      end
      def main()
        let empty = nil
        let truth\t=\ttrue;let count=12# binding separator
        let text = "fixed"
        consume(empty, truth, count, text)
      end
    DAB
    document = parse(source)
    bindings = document.declarations.fetch(1).body_items.grep(DabModernBootstrapLocalBinding)
    call = document.declarations.fetch(1).body_items.fetch(-1)

    expect(bindings).to all(be_frozen)
    expect(bindings.map(&:kind)).to all(eq(:let_binding))
    expect(bindings.map(&:name)).to eq(%w[empty truth count text])
    expect(bindings.map { |binding| binding.initializer_token.kind }).to eq(
      %i[nil boolean_true integer string]
    )
    expect(bindings.map { |binding| binding.source_tokens.map(&:text).join }).to eq(
      ['let empty = nil', "let truth\t=\ttrue", 'let count=12', 'let text = "fixed"']
    )
    expect(bindings.map { |binding| [binding.source_span.start_offset, binding.source_span.end_offset] }).to eq(
      bindings.map do |binding|
        text = binding.source_tokens.map(&:text).join
        start = source.index(text)
        [start, start + text.bytesize]
      end
    )

    expect(call.arguments).to all(be_a(DabModernBootstrapLocalReference))
    expect(call.arguments).to all(be_frozen)
    expect(call.arguments.map(&:kind)).to all(eq(:local_reference))
    expect(call.arguments.map(&:name)).to eq(%w[empty truth count text])
    expect(call.arguments.map { |argument| argument.source_tokens.map(&:text).join }).to eq(
      %w[empty truth count text]
    )

    functions = document.lower_into(DabNodeUnit.new)
    main = functions.fetch(1)
    definitions = main.blocks[0].all_nodes(DabNodeDefineLocalVar)
    references = main.blocks[0].all_nodes(DabNodeLocalVar)
    expect(definitions.map(&:real_identifier)).to eq(%w[empty truth count text])
    expect(definitions.map { |definition| definition.my_type.type_string }).to all(eq('Object'))
    expect(references.map(&:real_identifier)).to eq(%w[empty truth count text])
    expect(definitions.map { |definition| [definition.source_cstart, definition.source_cend] }).to eq(
      bindings.map { |binding| [binding.source_span.start_offset, binding.source_span.end_offset] }
    )
    expect(references.map { |reference| [reference.source_cstart, reference.source_cend] }).to eq(
      call.arguments.map { |argument| [argument.source_span.start_offset, argument.source_span.end_offset] }
    )
  end

  it 'uses declaration-point scope and rejects duplicates and parameter collisions at the binding name' do
    read_before = "def main()\nprint(value)\nlet value = \"later\"\nend\n"
    expect do
      parse(read_before)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [read_before.index('value'), read_before.index('value') + 5]
      )
    }

    duplicate = "def main()\nlet value = 1\nlet value = 2\nend\n"
    expect do
      parse(duplicate)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('duplicate Modern local binding "value"')
      second_name = duplicate.rindex('value')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [second_name, second_name + 5]
      )
    }

    parameter_collision = "def main(value:String)\nlet value = \"local\"\nend\n"
    expect do
      parse(parameter_collision)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('Modern local binding "value" conflicts with parameter "value"')
      binding_name = parameter_collision.rindex('value')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [binding_name, binding_name + 5]
      )
    }

    cross_function = <<~DAB
      def first()
      let value = "first"
      end
      def second()
      print(value)
      end
    DAB
    expect do
      parse(cross_function)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      reference = cross_function.rindex('value')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [reference, reference + 5]
      )
    }
  end

  it 'allows separate-function reuse and callable, builtin, and lower-Ring spelling collisions' do
    source = <<~DAB
      def let()
      end
      def helper()
      end
      def first()
      let helper = "first"
      helper()
      print(helper)
      end
      def second()
      let print = "second"
      let lower = "ring"
      print(print)
      print(lower)
      let()
      end
    DAB
    unit = DabNodeUnit.new
    unit.add_function(DabNodeFunctionStub.new('lower', nil, is_static: false))
    functions = parse(source).lower_into(unit)

    expect(functions.map(&:identifier)).to eq(%w[let helper first second])
    calls = functions.flat_map { |function| function.blocks[0].all_nodes(DabNodeCall) }
    expect(calls.map(&:real_identifier)).to eq(%w[helper print print print let])
    expect(calls.flat_map(&:args).grep(DabNodeLocalVar).map(&:real_identifier)).to eq(
      %w[helper print lower]
    )
  end

  it 'uses initializer literal precision only for same-document call preflight' do
    accepted = <<~DAB
      def take_string(value:String)
      end
      def take_object(value:Float)
      end
      def main()
      let text = "value"
      let count = 1
      take_string(text)
      end
    DAB
    functions = parse(accepted).lower_into(DabNodeUnit.new)
    definition = functions.fetch(-1).blocks[0].all_nodes(DabNodeDefineLocalVar).fetch(0)
    expect(definition.my_type.type_string).to eq('Object')

    mismatch = <<~DAB
      def take(value:String)
      end
      def main()
      let count = 1
      take(count)
      end
    DAB
    expect do
      parse(mismatch).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "take"'
      )
      reference = mismatch.index('count', mismatch.index('take(count)'))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [reference, reference + 5]
      )
    }
  end

  it 'contains local-bearing print calls to exactly one total argument' do
    source = <<~DAB
      def main()
      let first = "a"
      let second = "b"
      print(first, second)
      end
    DAB
    expect do
      parse(source).lower_into(DabNodeUnit.new)
    end.to raise_error(
      DabModernBootstrapParseError,
      'incorrect Modern call arity for "print": got 2, expected 1'
    )

    functions = parse("def main()\nlet value = \"x\"\nprint(value)\nprint(1,2)\nend\n").lower_into(DabNodeUnit.new)
    calls = functions.blocks[0].all_nodes(DabNodeCall)
    expect(calls.map { |call| call.args.length }).to eq([1, 1, 1])
    expect(calls.fetch(0).args.fetch(0)).to be_a(DabNodeLocalVar)
  end

  it 'keeps let contextual while emitting only proven binding diagnostics' do
    callable = "def let()\nend\ndef main()\nlet()\nend\n"
    functions = parse(callable).lower_into(DabNodeUnit.new)
    expect(functions.map(&:identifier)).to eq(%w[let main])
    expect(functions.fetch(1).blocks[0].all_nodes(DabNodeCall).map(&:real_identifier)).to eq(['let'])

    cases = {
      'space' => ["def main()\nlet\tvalue = nil\nend\n", DabModernBootstrapParser::EXPECT_LET_SPACE_MESSAGE, "\t"],
      'name' => ["def main()\nlet = nil\nend\n", DabModernBootstrapParser::EXPECT_LET_NAME_MESSAGE, '='],
      'equal' => ["def main()\nlet value\nend\n", DabModernBootstrapParser::EXPECT_LET_EQUAL_MESSAGE, "\n"],
      'initializer' => ["def main()\nlet value =\nend\n", DabModernBootstrapParser::EXPECT_LET_INITIALIZER_MESSAGE, "\n"],
      'separator' => ["def main()\nlet value = nil \nend\n", DabModernBootstrapParser::EXPECT_LET_SEPARATOR_MESSAGE, ' '],
    }
    cases.each do |description, (source, message, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(offending), description
      }
    end

    generic_cases = {
      'reassignment' => ["def main()\nlet value = nil\nvalue = true\nend\n", 'value'],
      'annotation' => ["def main()\nlet value : String = \"x\"\nend\n", ':'],
      'nonliteral initializer' => ["def main()\nlet value = other\nend\n", 'other'],
      'nested call initializer' => ["def main()\nlet value = make()\nend\n", 'make'],
    }
    generic_cases.each do |description, (source, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        start = if description == 'reassignment'
                  source.rindex(offending)
                else
                  source.index(offending, source.index("\n") + 1)
                end
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [start, start + offending.bytesize]
        ), description
      }
    end
  end

  it 'preserves exact CR spans, closed whitespace, and local-reference grammar boundaries' do
    ["\r", "\r\n"].each do |ending|
      source = "def main()\nlet value = nil#{ending}end\n"
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE)
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(ending)
      }
    end

    generic_cases = {
      'line-start TAB' => ["def main()\n\tlet value = nil\nend\n", "\t"],
      'local body item' => ["def main()\nlet value = nil\nvalue\nend\n", 'value'],
      'local initializer' => ["def main()\nlet first = nil\nlet second = first\nend\n", 'first'],
      'local receiver' => ["def main()\nlet value = \"x\"\nvalue.length\nend\n", 'value'],
      'nested local call' => ["def main()\nlet value = \"x\"\nprint(value())\nend\n", 'value'],
    }
    generic_cases.each do |description, (source, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(offending), description
      }
    end
  end

  it 'parses the complete document before local preflight and performs local preflight before Ring I/O' do
    later_structural_error = <<~DAB
      def main()
      let value = 1
      let value = 2
      print(,)
      end
    DAB
    expect do
      parse(later_structural_error)
    end.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    Dir.mktmpdir('dab-modern-local-preflight') do |directory|
      source_path = File.join(directory, 'duplicate.dabm')
      File.binwrite(source_path, "def main()\nlet value = 1\nlet value = 2\nend\n")
      missing_ring = File.join(directory, 'missing.dabcb')

      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:3:4: error: duplicate Modern local binding \"value\"\n"
      )
      expect(File).not_to exist(missing_ring)
    end
  end

  it 'preflights all calls before lowering any accepted local binding' do
    unit = DabNodeUnit.new
    original_functions = unit.functions.to_a
    original_constants = unit.constants.to_a
    source = <<~DAB
      def first()
      let value = "accepted"
      print(value)
      end
      def second()
      missing()
      end
    DAB

    expect do
      parse(source).lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError, 'unknown Modern call target "missing"')
    expect(unit.functions.to_a).to eq(original_functions)
    expect(unit.constants.to_a).to eq(original_constants)
  end
end
