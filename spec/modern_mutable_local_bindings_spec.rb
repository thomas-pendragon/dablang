require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern mutable local bindings' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'mutable-local-bindings.dabm',
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

  it 'retains immutable mutable-binding and reassignment source parts and reuses local SSA flow' do
    source = <<~DAB
      def main()
      var value\t=\t"first"
      print(value)
      value = "second"# write separator
      print(value)
      end
    DAB
    document = parse(source)
    items = document.declarations.fetch(0).body_items
    binding = items.fetch(0)
    first_call = items.fetch(1)
    reassignment = items.fetch(2)
    second_call = items.fetch(3)

    expect(binding).to be_a(DabModernBootstrapMutableLocalBinding)
    expect(binding).to be_frozen
    expect(binding.kind).to eq(:var_binding)
    expect(binding.name).to eq('value')
    expect(binding.source_tokens.map(&:text).join).to eq("var value\t=\t\"first\"")
    expect(reassignment).to be_a(DabModernBootstrapLocalReassignment)
    expect(reassignment).to be_frozen
    expect(reassignment.kind).to eq(:var_reassignment)
    expect(reassignment.source_tokens.map(&:text).join).to eq('value = "second"')

    function = document.lower_into(DabNodeUnit.new)
    definition = function.blocks[0].all_nodes(DabNodeDefineLocalVar).fetch(0)
    setter = function.blocks[0].all_nodes(DabNodeSetLocalVar).reject do |node|
      node.is_a?(DabNodeDefineLocalVar)
    end.fetch(0)
    references = function.blocks[0].all_nodes(DabNodeLocalVar)
    expect([definition.my_type.type_string, setter.my_type.type_string]).to eq(%w[Object Object])
    expect(references.map(&:real_identifier)).to eq(%w[value value])
    expect(references.fetch(0).last_var_setter).to equal(definition)
    expect(references.fetch(1).last_var_setter).to equal(setter)
    expect([definition.source_cstart, definition.source_cend]).to eq(
      [binding.source_span.start_offset, binding.source_span.end_offset]
    )
    expect([setter.source_cstart, setter.source_cend]).to eq(
      [reassignment.source_span.start_offset, reassignment.source_span.end_offset]
    )
    expect(first_call.arguments.fetch(0).name).to eq(second_call.arguments.fetch(0).name)
  end

  it 'uses each latest literal write for bounded same-document call preflight' do
    source = <<~DAB
      def take_nil(value:NilClass)
      end
      def take_bool(value:Boolean)
      end
      def take_int(value:Fixnum)
      end
      def take_string(value:String)
      end
      def main()
      var value = nil
      take_nil(value)
      value = true
      take_bool(value)
      value = 12
      take_int(value)
      value = "text"
      take_string(value)
      end
    DAB
    document = parse(source)
    expect { document.lower_into(DabNodeUnit.new) }.not_to raise_error
    writes = document.declarations.fetch(-1).body_items.select do |item|
      item.is_a?(DabModernBootstrapMutableLocalBinding) ||
        item.is_a?(DabModernBootstrapLocalReassignment)
    end
    expect(writes.map { |write| write.initializer_type.type_string }).to eq(
      %w[NilClass Boolean Fixnum String]
    )

    mismatch = <<~DAB
      def take(value:String)
      end
      def main()
      var value = "first"
      value = 1
      take(value)
      end
    DAB
    expect do
      parse(mismatch).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "take"'
      )
      reference = mismatch.index('value', mismatch.index('take(value)'))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [reference, reference + 5]
      )
    }
  end

  it 'keeps var contextual and permits callable, builtin, and lower-Ring spelling collisions' do
    source = <<~DAB
      def var()
      end
      def helper()
      end
      def main()
      var var = "first"
      var()
      print(var)
      var = "second"
      var helper = "local"
      helper()
      print(helper)
      var print = "builtin"
      print(print)
      var lower = "ring"
      print(lower)
      end
    DAB
    unit = DabNodeUnit.new
    unit.add_function(DabNodeFunctionStub.new('lower', nil, is_static: false))
    functions = parse(source).lower_into(unit)
    calls = functions.flat_map { |function| function.blocks[0].all_nodes(DabNodeCall) }

    expect(functions.map(&:identifier)).to eq(%w[var helper main])
    expect(calls.map(&:real_identifier)).to eq(%w[var print helper print print print])
    expect(calls.flat_map(&:args).grep(DabNodeLocalVar).map(&:real_identifier)).to eq(
      %w[var helper print lower]
    )
  end

  it 'enforces declaration-point scope and uniform local collisions' do
    generic_cases = {
      'read-before reassignment' => "def main()\nvalue = 1\nvar value = 2\nend\n",
      'fixed let reassignment' => "def main()\nlet value = 1\nvalue = 2\nend\n",
      'fixed let named var reassignment' => "def main()\nlet var = 1\nvar = 2\nend\n",
    }
    generic_cases.each do |description, source|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        target = source.byteslice(error.source_span.start_offset...error.source_span.end_offset)
        expect(target).to match(/\A(?:value|var)\z/), description
      }
    end

    collisions = {
      'let then var' => "def main()\nlet value = 1\nvar value = 2\nend\n",
      'var then let' => "def main()\nvar value = 1\nlet value = 2\nend\n",
      'var then var' => "def main()\nvar value = 1\nvar value = 2\nend\n",
    }
    collisions.each do |description, source|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq('duplicate Modern local binding "value"'), description
        name = source.rindex('value')
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([name, name + 5])
      }
    end

    let_then_var_then_write = <<~DAB
      def main()
      let value = 1
      var value = 2
      value = 3
      end
    DAB
    expect do
      parse(let_then_var_then_write)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('duplicate Modern local binding "value"')
      declaration = let_then_var_then_write.index('value', let_then_var_then_write.index('var value'))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [declaration, declaration + 5]
      )
    }

    parameter = "def main(value:String)\nvar value = \"local\"\nend\n"
    expect do
      parse(parameter)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('Modern local binding "value" conflicts with parameter "value"')
      name = parameter.rindex('value')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([name, name + 5])
    }

    reuse = "def first()\nvar value = 1\nend\ndef second()\nvar value = 2\nend\n"
    expect(parse(reuse).lower_into(DabNodeUnit.new).map(&:identifier)).to eq(%w[first second])
  end

  it 'emits only the seven proven mutable-local diagnostics with exact spans' do
    cases = {
      'binding space' => ["def main()\nvar\tvalue = nil\nend\n", DabModernBootstrapParser::EXPECT_VAR_SPACE_MESSAGE, "\t"],
      'binding name' => ["def main()\nvar = nil\nend\n", DabModernBootstrapParser::EXPECT_VAR_NAME_MESSAGE, '='],
      'binding equal' => ["def main()\nvar value\nend\n", DabModernBootstrapParser::EXPECT_VAR_EQUAL_MESSAGE, "\n"],
      'binding initializer' => ["def main()\nvar value =\nend\n", DabModernBootstrapParser::EXPECT_VAR_INITIALIZER_MESSAGE, "\n"],
      'binding separator' => ["def main()\nvar value = nil \nend\n", DabModernBootstrapParser::EXPECT_VAR_SEPARATOR_MESSAGE, ' '],
      'write value' => ["def main()\nvar value = nil\nvalue =\nend\n", DabModernBootstrapParser::EXPECT_REASSIGNMENT_VALUE_MESSAGE, "\n"],
      'write separator' => ["def main()\nvar value = nil\nvalue = true \nend\n", DabModernBootstrapParser::EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE, ' '],
    }
    cases.each do |description, (source, message, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(offending)
      }
    end

    eof_cases = {
      "def main()\nvar" => DabModernBootstrapParser::EXPECT_VAR_SPACE_MESSAGE,
      "def main()\nvar " => DabModernBootstrapParser::EXPECT_VAR_NAME_MESSAGE,
      "def main()\nvar value" => DabModernBootstrapParser::EXPECT_VAR_EQUAL_MESSAGE,
      "def main()\nvar value =" => DabModernBootstrapParser::EXPECT_VAR_INITIALIZER_MESSAGE,
      "def main()\nvar value = nil" => DabModernBootstrapParser::EXPECT_VAR_SEPARATOR_MESSAGE,
      "def main()\nvar value = nil\nvalue =" => DabModernBootstrapParser::EXPECT_REASSIGNMENT_VALUE_MESSAGE,
      "def main()\nvar value = nil\nvalue = true" => DabModernBootstrapParser::EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE,
    }
    eof_cases.each do |source, message|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message)
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [source.bytesize, source.bytesize]
        )
      }
    end
  end

  it 'reports each dedicated diagnostic once with status 2 and no partial assembly' do
    cases = {
      'space' => ["def main()\nvar\tvalue = nil\nend\n", 2, 3, DabModernBootstrapParser::EXPECT_VAR_SPACE_MESSAGE],
      'name' => ["def main()\nvar = nil\nend\n", 2, 4, DabModernBootstrapParser::EXPECT_VAR_NAME_MESSAGE],
      'equal' => ["def main()\nvar value\nend\n", 3, 0, DabModernBootstrapParser::EXPECT_VAR_EQUAL_MESSAGE],
      'initializer' => ["def main()\nvar value =\nend\n", 3, 0, DabModernBootstrapParser::EXPECT_VAR_INITIALIZER_MESSAGE],
      'binding separator' => ["def main()\nvar value = nil \nend\n", 2, 15, DabModernBootstrapParser::EXPECT_VAR_SEPARATOR_MESSAGE],
      'write value' => ["def main()\nvar value = nil\nvalue =\nend\n", 4, 0, DabModernBootstrapParser::EXPECT_REASSIGNMENT_VALUE_MESSAGE],
      'write separator' => ["def main()\nvar value = nil\nvalue = true \nend\n", 3, 12, DabModernBootstrapParser::EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE],
    }

    Dir.mktmpdir('dab-modern-mutable-local-diagnostics') do |directory|
      missing_ring = File.join(directory, 'missing.dabcb')
      cases.each do |description, (source, line, column, message)|
        source_path = File.join(directory, "#{description.tr(' ', '-')}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{missing_ring}"
        )

        expect([status.exitstatus, stdout]).to eq([2, '']), description
        expect(tool_stderr(stderr)).to eq(
          "compiler: #{source_path}:#{line}:#{column}: error: #{message}\n"
        ), description
        expect(File).not_to exist(missing_ring)
      end
    end
  end

  it 'retains generic nonliteral and operator boundaries and CR separator precedence' do
    generic_cases = {
      'nonliteral RHS' => ["def main()\nvar value = nil\nvalue = other\nend\n", 'other'],
      'nonliteral equal RHS' => ["def main()\nvar value = nil\nvalue = =\nend\n", '='],
      'local RHS' => ["def main()\nvar value = nil\nvar other = 1\nvalue = other\nend\n", 'other'],
      'call RHS' => ["def main()\nvar value = nil\nvalue = make()\nend\n", 'make'],
      'equality' => ["def main()\nvar value = nil\nvalue == true\nend\n", 'value'],
      'member RHS' => ["def main()\nvar value = nil\nvalue = \"x\".length\nend\n", '.'],
      'typed var' => ["def main()\nvar value : String = \"x\"\nend\n", ':'],
      'standalone read' => ["def main()\nvar value = nil\nvalue\nend\n", 'value'],
      'local receiver' => ["def main()\nvar value = \"x\"\nvalue.length\nend\n", 'value'],
      'nested local call' => ["def main()\nvar value = \"x\"\nprint(value())\nend\n", 'value'],
    }
    generic_cases.each do |description, (source, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(offending)
      }
    end

    ["\r", "\r\n"].each do |ending|
      cases = {
        DabModernBootstrapParser::EXPECT_VAR_SPACE_MESSAGE => "def main()\nvar#{ending}end\n",
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE => [
          "def main()\nvar #{ending}end\n",
          "def main()\nvar value#{ending}end\n",
          "def main()\nvar value =#{ending}end\n",
          "def main()\nvar value = nil#{ending}end\n",
          "def main()\nvar value = nil\nvalue =#{ending}end\n",
          "def main()\nvar value = nil\nvalue = true#{ending}end\n",
        ],
      }
      cases.each do |message, sources|
        Array(sources).each do |source|
          expect do
            parse(source)
          end.to raise_error(DabModernBootstrapParseError) { |error|
            expect(error.message).to eq(message)
            expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(ending)
          }
        end
      end
    end
  end

  it 'keeps local-containing print unary and validates the complete document before local preflight' do
    multi_print = <<~DAB
      def main()
      var first = "a"
      var second = "b"
      first = "c"
      print(first, second)
      end
    DAB
    expect do
      parse(multi_print).lower_into(DabNodeUnit.new)
    end.to raise_error(
      DabModernBootstrapParseError,
      'incorrect Modern call arity for "print": got 2, expected 1'
    )

    later_structural_error = <<~DAB
      def main()
      var value = 1
      var value = 2
      print(,)
      end
    DAB
    expect do
      parse(later_structural_error)
    end.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )
  end

  it 'performs mutable-local preflight before Ring I/O and call preflight before lowering' do
    Dir.mktmpdir('dab-modern-mutable-local-preflight') do |directory|
      source_path = File.join(directory, 'duplicate.dabm')
      File.binwrite(source_path, "def main()\nvar value = 1\nvar value = 2\nend\n")
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

    unit = DabNodeUnit.new
    source = <<~DAB
      def first()
      var value = "accepted"
      value = "changed"
      print(value)
      end
      def second()
      missing()
      end
    DAB
    expect do
      parse(source).lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError, 'unknown Modern call target "missing"')
    expect(unit.functions.to_a).to be_empty
    expect(unit.constants.to_a).to be_empty
  end
end
