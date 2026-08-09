require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern typed local bindings' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'typed-local-bindings.dabm',
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

  def expect_parse_error(source, message, offending, occurrence: :first)
    expect do
      parse(source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      start = occurrence == :last ? source.rindex(offending) : source.index(offending)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
    }
  end

  it 'accepts optional annotations on let and var with exact horizontal whitespace and source spans' do
    source = <<~DAB
      def main()
      let fixed:String="fixed"
      var mutable \t: \tString\t =\t"first"
      mutable = "second"
      end
    DAB
    document = parse(source)
    fixed, mutable, write = document.declarations.fetch(0).body_items

    expect(fixed).to be_a(DabModernBootstrapLocalBinding)
    expect(mutable).to be_a(DabModernBootstrapMutableLocalBinding)
    expect(write).to be_a(DabModernBootstrapLocalReassignment)
    expect([fixed.type_name.text, mutable.type_name.text, write.type_name.text]).to eq(
      %w[String String String]
    )
    expect([fixed.declared_type.type_string, mutable.declared_type.type_string]).to eq(
      %w[String String]
    )
    expect(fixed.source_tokens.map(&:text).join).to eq('let fixed:String="fixed"')
    expect(mutable.source_tokens.map(&:text).join).to eq("var mutable \t: \tString\t =\t\"first\"")
    expect(write.source_tokens.map(&:text).join).to eq('mutable = "second"')
    expect([fixed.source_span.start_offset, fixed.source_span.end_offset]).to eq(
      [source.index('let fixed'), source.index('let fixed') + 'let fixed:String="fixed"'.bytesize]
    )
  end

  it 'accepts exactly the fourteen R38 names under the current literal assignment relation' do
    accepted_initializers = {
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
    expect(accepted_initializers.keys).to eq(DabModernBootstrapParser::SUPPORTED_TYPE_NAMES)

    accepted_initializers.each do |type_name, initializer|
      %w[let var].each do |keyword|
        source = "def main()\n#{keyword} value : #{type_name} = #{initializer}\nend\n"
        expect { parse(source) }.not_to raise_error, "#{keyword} #{type_name}"
      end
    end

    DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.each do |type_name|
      source = "def main()\nlet value : #{type_name} = nil\nend\n"
      expect { parse(source) }.not_to raise_error, "nil to #{type_name}"
    end
  end

  it 'lowers typed definitions and every typed write with the declared type' do
    source = <<~DAB
      def main()
      let fixed : String = "fixed"
      var count : Int32 = 1
      count = 2
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    definitions = function.blocks[0].all_nodes(DabNodeDefineLocalVar)
    setter = function.blocks[0].all_nodes(DabNodeSetLocalVar).reject do |node|
      node.is_a?(DabNodeDefineLocalVar)
    end.fetch(0)

    expect(definitions.map { |definition| definition.my_type.type_string }).to eq(%w[String Int32])
    expect(setter.my_type.type_string).to eq('Int32')
  end

  it 'retains the declared numeric type through compiler conversion after a mutable write' do
    source = <<~DAB
      def main()
      var value : Int32 = 1
      value = 2
      print(value)
      end
    DAB
    Dir.mktmpdir('dab-modern-typed-local-int32') do |directory|
      lower = File.join(directory, 'stdlib.dabcb')
      source_path = File.join(directory, 'typed-int32.dabm')
      File.binwrite(source_path, source)
      stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{lower}")
      expect([status.exitstatus, stdout]).to eq([0, "PASS #{lower}\n"])
      expect(stderr).not_to include('exception:', 'FAILED')

      assembly, compiler_stderr, compiler_status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{lower}"
      )
      expect([compiler_status.exitstatus, tool_stderr(compiler_stderr)]).to eq([0, ''])
      expect(assembly).to include('LOAD_INT32 R0, 2')
      expect(assembly).not_to include('LOAD_NUMBER')
    end
  end

  it 'uses a typed declaration for call compatibility while preserving untyped latest-write flow' do
    accepted = <<~DAB
      def take(value:String)
      end
      def main()
      var value : String = nil
      take(value)
      value = "text"
      take(value)
      end
    DAB
    expect { parse(accepted).lower_into(DabNodeUnit.new) }.not_to raise_error

    declared_mismatch = <<~DAB
      def take(value:NilClass)
      end
      def main()
      var value : String = nil
      take(value)
      end
    DAB
    expect do
      parse(declared_mismatch).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot pass Modern argument of type String to parameter "value" of type NilClass in call "take"'
      )
      reference = declared_mismatch.index('value', declared_mismatch.index('take(value)'))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [reference, reference + 5]
      )
    }

    untyped = <<~DAB
      def take_nil(value:NilClass)
      end
      def take_string(value:String)
      end
      def main()
      var value = nil
      take_nil(value)
      value = "text"
      take_string(value)
      end
    DAB
    expect { parse(untyped).lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'emits the six typed-local diagnostic families with exact token spans' do
    invalid_type = "def main()\nlet value : = \"x\"\nend\n"
    expect_parse_error(
      invalid_type,
      DabModernBootstrapParser::EXPECT_LOCAL_TYPE_MESSAGE,
      '='
    )

    unknown_type = "def main()\nlet value : Object = nil\nend\n"
    expect_parse_error(
      unknown_type,
      'unknown Modern type "Object"; supported types are String, Fixnum, Boolean, Uint8, ' \
      'Uint16, Uint32, Uint64, Int8, Int16, Int32, Int64, IntPtr, NilClass, and Float',
      'Object'
    )

    missing_let_equal = "def main()\nlet value : String nil\nend\n"
    expect_parse_error(
      missing_let_equal,
      DabModernBootstrapParser::EXPECT_TYPED_LET_EQUAL_MESSAGE,
      'nil'
    )

    missing_var_equal = "def main()\nvar value : String nil\nend\n"
    expect_parse_error(
      missing_var_equal,
      DabModernBootstrapParser::EXPECT_TYPED_VAR_EQUAL_MESSAGE,
      'nil'
    )

    initializer_mismatch = "def main()\nlet value : String = 1\nend\n"
    expect_parse_error(
      initializer_mismatch,
      'cannot initialize Modern local "value" of type String with literal of type Fixnum',
      '1'
    )

    write_mismatch = "def main()\nvar value : String = nil\nvalue = 1\nend\n"
    expect_parse_error(
      write_mismatch,
      'cannot assign Modern literal of type Fixnum to local "value" of type String',
      '1',
      occurrence: :last
    )
  end

  it 'uses zero-width EOF spans and preserves CR separator precedence inside annotations' do
    {
      "def main()\nlet value :" => DabModernBootstrapParser::EXPECT_LOCAL_TYPE_MESSAGE,
      "def main()\nlet value : String" => DabModernBootstrapParser::EXPECT_TYPED_LET_EQUAL_MESSAGE,
    }.each do |source, message|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message)
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
          [source.bytesize, source.bytesize]
        )
      }
    end

    ["\r", "\r\n"].each do |ending|
      source = "def main()\nlet value :#{ending}end\n"
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE)
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(ending)
      }
    end
  end

  it 'keeps typed reassignment syntax and broader type forms outside the grammar' do
    generic_cases = {
      'typed reassignment' => ["def main()\nvar value : String = nil\nvalue : String = \"x\"\nend\n", 'value'],
      'nullable type' => ["def main()\nlet value : String? = nil\nend\n", '?'],
      'generic type' => ["def main()\nlet value : Array[String] = nil\nend\n", 'Array'],
    }
    generic_cases.each do |description, (source, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        if description == 'generic type'
          expect(error.message).to match(/unknown Modern type "Array"/)
        elsif description == 'nullable type'
          expect(error.message).to eq(DabModernBootstrapParser::EXPECT_TYPED_LET_EQUAL_MESSAGE)
        else
          expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
        end
        target = source.byteslice(error.source_span.start_offset...error.source_span.end_offset)
        expect(target).to eq(offending), description
      }
    end
  end

  it 'finishes document parsing and all typed-local checks before Ring I/O or lowering mutation' do
    later_structural_error = <<~DAB
      def main()
      let value : String = 1
      print(,)
      end
    DAB
    expect do
      parse(later_structural_error)
    end.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    unit = DabNodeUnit.new
    original_functions = unit.functions.to_a
    original_constants = unit.constants.to_a
    call_error = <<~DAB
      def main()
      let value : String = "accepted"
      missing()
      end
    DAB
    expect do
      parse(call_error).lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError, 'unknown Modern call target "missing"')
    expect(unit.functions.to_a).to eq(original_functions)
    expect(unit.constants.to_a).to eq(original_constants)

    Dir.mktmpdir('dab-modern-typed-local-preflight') do |directory|
      source_path = File.join(directory, 'typed-mismatch.dabm')
      File.binwrite(source_path, "def main()\nvar value : String = nil\nvalue = 1\nend\n")
      missing_ring = File.join(directory, 'missing.dabcb')
      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:3:8: error: " \
        "cannot assign Modern literal of type Fixnum to local \"value\" of type String\n"
      )
      expect(File).not_to exist(missing_ring)
    end
  end

  it 'reports every typed-local family through the compiler with status 2 and empty stdout' do
    cases = {
      'invalid-type' => [
        "def main()\nlet value : = \"x\"\nend\n",
        2,
        12,
        DabModernBootstrapParser::EXPECT_LOCAL_TYPE_MESSAGE,
      ],
      'unknown-type' => [
        "def main()\nlet value : Object = nil\nend\n",
        2,
        12,
        'unknown Modern type "Object"; supported types are String, Fixnum, Boolean, Uint8, ' \
        'Uint16, Uint32, Uint64, Int8, Int16, Int32, Int64, IntPtr, NilClass, and Float',
      ],
      'let-equal' => [
        "def main()\nlet value : String nil\nend\n",
        2,
        19,
        DabModernBootstrapParser::EXPECT_TYPED_LET_EQUAL_MESSAGE,
      ],
      'var-equal' => [
        "def main()\nvar value : String nil\nend\n",
        2,
        19,
        DabModernBootstrapParser::EXPECT_TYPED_VAR_EQUAL_MESSAGE,
      ],
      'initializer' => [
        "def main()\nlet value : String = 1\nend\n",
        2,
        21,
        'cannot initialize Modern local "value" of type String with literal of type Fixnum',
      ],
      'write' => [
        "def main()\nvar value : String = nil\nvalue = 1\nend\n",
        3,
        8,
        'cannot assign Modern literal of type Fixnum to local "value" of type String',
      ],
    }

    Dir.mktmpdir('dab-modern-typed-local-diagnostics') do |directory|
      missing_ring = File.join(directory, 'missing.dabcb')
      cases.each do |name, (source, line, column, message)|
        source_path = File.join(directory, "#{name}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{missing_ring}"
        )

        expect([status.exitstatus, stdout]).to eq([2, '']), name
        expect(tool_stderr(stderr)).to eq(
          "compiler: #{source_path}:#{line}:#{column}: error: #{message}\n"
        ), name
        expect(File).not_to exist(missing_ring)
      end
    end
  end
end
