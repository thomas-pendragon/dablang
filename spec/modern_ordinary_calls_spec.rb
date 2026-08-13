require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern ordinary parenthesized calls' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'ordinary-calls.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
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

  def invoke(*command, input: nil)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-bundler')}
    Open3.capture3(environment, *command, stdin_data: input, chdir: root)
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

  def puts_stub(signature: puts_signature, is_static: false)
    DabNodeFunctionStub.new('puts', nil, is_static: is_static, ring_signature: signature)
  end

  def compile(source_path, lower)
    assembly, stderr, status = invoke(
      RbConfig.ruby,
      compiler,
      source_path,
      "--ring-base[]=#{lower}"
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    assembly
  end

  it 'retains direct-call body items, literal arguments, whitespace, suffixes, and exact spans' do
    source = <<~DAB
      def main
      ready?\t(\tnil , true,\t12 , "x"\t)
      end
      def ready?(a:NilClass,b:Boolean,c:Fixnum,d:String)
      end
    DAB
    document = parse(source)
    declaration = document.declarations.fetch(0)
    call = declaration.body_items.fetch(0)

    expect(call).to be_a(DabModernBootstrapDirectCall)
    expect(call.kind).to eq(:direct_call)
    expect(call.callable_name.text).to eq('ready?')
    expect(call.arguments.map(&:kind)).to eq(%i[nil boolean_true integer string])
    expect(call.arguments.map(&:value)).to eq(%w[nil true 12 x])
    expect([call.source_span.start_offset, call.source_span.end_offset]).to eq(
      [source.index('ready?'), source.index(")\n") + 1]
    )
    expect(call.source_tokens.map(&:text).join).to eq("ready?\t(\tnil , true,\t12 , \"x\"\t)")

    functions = document.lower_into(DabNodeUnit.new)
    lowered_call = functions.fetch(0).blocks[0].all_nodes(DabNodeCall).fetch(0)
    expect(lowered_call.real_identifier).to eq('ready?')
    expect(lowered_call.args.map(&:constant_value)).to eq([nil, true, 12, 'x'])
    expect([lowered_call.source_cstart, lowered_call.source_cend]).to eq(
      [call.source_span.start_offset, call.source_span.end_offset]
    )
  end

  it 'accepts zero and multiple literal arguments with LF, semicolon, or line-comment body separators' do
    source = <<~DAB
      def main
      zero()
      many(nil,false,0,"x");print()# body separator
      print(nil,true,1,"y")
      end
      def zero
      end
      def many(a:NilClass,b:Boolean,c:Fixnum,d:String)
      end
    DAB
    functions = parse(source).lower_into(DabNodeUnit.new)
    calls = functions.fetch(0).blocks[0].all_nodes(DabNodeCall)

    expect(calls.map(&:real_identifier)).to eq(%w[zero many print print print print])
    expect(calls.map { |call| call.args.length }).to eq([0, 4, 1, 1, 1, 1])
  end

  it 'uses all five direct-call syntax diagnostics with first-unmet-production spans' do
    cases = {
      'argument-or-close' => [
        "def main\ncall(,)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
        [14, 15],
      ],
      'argument-separator' => [
        "def main\ncall(1 2)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE,
        [16, 17],
      ],
      'argument-after-comma' => [
        "def main\ncall(1,)\nend\n",
        DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE,
        [16, 17],
      ],
      'unterminated' => [
        "def main\ncall(",
        DabModernBootstrapParser::EXPECT_CALL_CLOSE_MESSAGE,
        [14, 14],
      ],
      'body-separator' => [
        "def main\ncall() \nend\n",
        DabModernBootstrapParser::EXPECT_CALL_BODY_SEPARATOR_MESSAGE,
        [15, 16],
      ],
    }

    cases.each do |description, (source, message, span)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(span), description
        expect(error.source_span.source_unit).to equal(source_unit)
      }
    end
  end

  it 'rejects comma and internal line-break near misses at their exact tokens' do
    cases = {
      'doubled comma' => ["def main\ncall(1,,2)\nend\n", 16, DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE],
      'missing comma' => ["def main\ncall(1 true)\nend\n", 16, DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE],
      'line feed before argument' => ["def main\ncall(\n)\nend\n", 14, DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE],
      'comment before argument' => ["def main\ncall(# no\n)\nend\n", 14, DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE],
      'line feed after argument' => ["def main\ncall(1\n)\nend\n", 15, DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE],
      'line feed after comma' => ["def main\ncall(1,\n)\nend\n", 16, DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE],
    }

    cases.each do |description, (source, offset, message)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(error.source_span.start_offset).to eq(offset), description
      }
    end

    ["def main\ncall(\r)\nend\n", "def main\ncall(\r\n)\nend\n"].each do |source|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE)
        expect(error.source_span.end_offset - error.source_span.start_offset).to eq(source.include?("\r\n") ? 2 : 1)
      }
    end
  end

  it 'admits parameter arguments while keeping dot calls, operators, and top-level calls deferred' do
    expect { parse("def main(value:String)\nprint(value)\nend\n") }.not_to raise_error

    cases = {
      'dot call' => ["def main\nvalue.call()\nend\n", 9],
      'operator argument' => ["def main\nprint(+1)\nend\n", 15],
      'top-level call' => ["print()\n", 0],
    }

    cases.each do |description, (source, offset)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(error.source_span.start_offset).to eq(offset), description
      }
    end
  end

  it 'preflights forward calls, recursion, suffix names, arity, and current assignability' do
    accepted = <<~DAB
      def main
      target(nil,true,false)
      recurse()
      ready?()
      save!()
      end
      def target(string:String,number:Fixnum,boolean:Boolean)
      end
      def recurse
      recurse()
      end
      def ready?
      end
      def save!
      end
    DAB
    functions = parse(accepted).lower_into(DabNodeUnit.new)
    expect(functions.map(&:identifier)).to eq(%w[main target recurse ready? save!])

    arity_source = "def main\ntarget(1)\nend\ndef target(a:Fixnum,b:String)\nend\n"
    arity_call = 'target(1)'
    expect do
      parse(arity_source).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('incorrect Modern call arity for "target": got 1, expected 2')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [arity_source.index(arity_call), arity_source.index(arity_call) + arity_call.length]
      )
    }

    type_source = "def main\ntarget(1)\nend\ndef target(value:String)\nend\n"
    expect do
      parse(type_source).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(
        'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "target"'
      )
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [type_source.index('1'), type_source.index('1') + 1]
      )
    }
  end

  it 'distinguishes unknown, unsupported, variadic print, and exact puts capability failures' do
    unknown_source = "def main\nmissing?()\nend\n"
    expect do
      parse(unknown_source).lower_into(DabNodeUnit.new)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq('unknown Modern call target "missing?"')
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([9, 17])
    }

    expect do
      parse("def main\nexit()\nend\n").lower_into(DabNodeUnit.new)
    end.to raise_error(
      DabModernBootstrapParseError,
      'unsupported Modern call target "exit" in the R39 ordinary-call subset'
    )

    print_function = parse("def main\nprint()\nprint(nil,true,1,\"x\")\nend\n").lower_into(DabNodeUnit.new)
    expect(print_function.blocks[0].all_nodes(DabNodeCall).map { |call| call.args.length }).to eq([1, 1, 1, 1])

    expect do
      parse("def main\nputs(\"x\")\nend\n").lower_into(DabNodeUnit.new)
    end.to raise_error(
      DabModernBootstrapParseError,
      'unsupported Modern call target "puts" in the R39 ordinary-call subset'
    )

    invalid_unit = DabNodeUnit.new
    invalid_unit.add_function(
      puts_stub(signature: {arguments: [].freeze, return_type: 'Object'}.freeze)
    )
    expect do
      parse("def main\nputs(\"x\")\nend\n").lower_into(invalid_unit)
    end.to raise_error(DabModernBootstrapParseError, /unsupported Modern call target "puts"/)

    renamed_argument_unit = DabNodeUnit.new
    renamed_argument_unit.add_function(
      puts_stub(
        signature: {
          arguments: [{name: 'value', type: 'Object'}.freeze].freeze,
          return_type: 'Object',
        }.freeze
      )
    )
    expect(parse("def main\nputs(\"x\")\nend\n").lower_into(renamed_argument_unit).identifier).to eq('main')

    wrong_type_unit = DabNodeUnit.new
    wrong_type_unit.add_function(
      puts_stub(
        signature: {
          arguments: [{name: 'string', type: 'String'}.freeze].freeze,
          return_type: 'Object',
        }.freeze
      )
    )
    expect do
      parse("def main\nputs(\"x\")\nend\n").lower_into(wrong_type_unit)
    end.to raise_error(DabModernBootstrapParseError, /unsupported Modern call target "puts"/)

    wrong_return_unit = DabNodeUnit.new
    wrong_return_unit.add_function(
      puts_stub(
        signature: {
          arguments: [{name: 'string', type: 'Object'}.freeze].freeze,
          return_type: 'NilClass',
        }.freeze
      )
    )
    expect do
      parse("def main\nputs(\"x\")\nend\n").lower_into(wrong_return_unit)
    end.to raise_error(DabModernBootstrapParseError, /unsupported Modern call target "puts"/)

    static_unit = DabNodeUnit.new
    static_unit.add_function(puts_stub(is_static: true))
    expect do
      parse("def main\nputs(\"x\")\nend\n").lower_into(static_unit)
    end.to raise_error(DabModernBootstrapParseError, /unsupported Modern call target "puts"/)

    valid_unit = DabNodeUnit.new
    valid_unit.add_function(puts_stub)
    expect do
      parse("def main\nputs()\nend\n").lower_into(valid_unit)
    end.to raise_error(
      DabModernBootstrapParseError,
      'incorrect Modern call arity for "puts": got 0, expected 1'
    )
    expect(parse("def main\nputs(nil)\nend\n").lower_into(valid_unit).identifier).to eq('main')
  end

  it 'lowers literal-only print arity to ordered unary calls with exact source spans' do
    source = "def main\nprint();print(nil,true,1,\"x\")\nend\n"
    document = parse(source)
    empty_call, multiple_call = document.declarations.fetch(0).body_items
    calls = document.lower_into(DabNodeUnit.new).blocks[0].all_nodes(DabNodeCall)

    expect(empty_call.arguments).to be_empty
    expect(calls.map(&:real_identifier)).to eq(%w[print print print print])
    expect(calls.map { |call| call.args.map(&:constant_value) }).to eq([[nil], [true], [1], ['x']])
    expect(calls.map { |call| [call.source_cstart, call.source_cend] }).to all(
      eq([multiple_call.source_span.start_offset, multiple_call.source_span.end_offset])
    )
    expect(calls.map { |call| [call.args.fetch(0).source_cstart, call.args.fetch(0).source_cend] }).to eq(
      multiple_call.arguments.map { |argument| [argument.source_span.start_offset, argument.source_span.end_offset] }
    )
  end

  it 'preflights every call before mutating the lower-Ring unit' do
    unit = DabNodeUnit.new
    unit.add_function(puts_stub)
    original_functions = unit.functions.map(&:identifier)
    original_constants = unit.constants.to_a
    source = <<~DAB
      def first
      print("accepted")
      end
      def second
      missing()
      end
    DAB

    expect do
      parse(source).lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError, 'unknown Modern call target "missing"')
    expect(unit.functions.map(&:identifier)).to eq(original_functions)
    expect(unit.constants.to_a).to eq(original_constants)
  end

  it 'reports call syntax before attempting to load a lower Ring' do
    Dir.mktmpdir('dab-modern-call-syntax-preflight') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      File.binwrite(source_path, "def main\nprint(,)\nend\n")
      missing_ring = File.join(directory, 'missing.dabcb')

      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:2:6: error: " \
        "#{DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE}\n"
      )
      expect(File).not_to exist(missing_ring)
    end
  end

  it 'emits all nine call diagnostics with status 2, empty stdout, and exact source locations' do
    Dir.mktmpdir('dab-modern-call-diagnostics') do |directory|
      lower = build_stdlib(directory)
      cases = {
        'argument-or-close' => [
          "def main\ncall(,)\nend\n",
          5,
          DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
        ],
        'argument-separator' => [
          "def main\ncall(1 2)\nend\n",
          7,
          DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE,
        ],
        'argument-after-comma' => [
          "def main\ncall(1,)\nend\n",
          7,
          DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE,
        ],
        'unterminated' => [
          "def main\ncall(",
          5,
          DabModernBootstrapParser::EXPECT_CALL_CLOSE_MESSAGE,
        ],
        'body-separator' => [
          "def main\ncall() \nend\n",
          6,
          DabModernBootstrapParser::EXPECT_CALL_BODY_SEPARATOR_MESSAGE,
        ],
        'unknown' => [
          "def main\nmissing()\nend\n",
          0,
          'unknown Modern call target "missing"',
        ],
        'unsupported' => [
          "def main\nexit()\nend\n",
          0,
          'unsupported Modern call target "exit" in the R39 ordinary-call subset',
        ],
        'arity' => [
          "def main\ntarget()\nend\ndef target(value:String)\nend\n",
          0,
          'incorrect Modern call arity for "target": got 0, expected 1',
        ],
        'type' => [
          "def main\ntarget(1)\nend\ndef target(value:String)\nend\n",
          7,
          'cannot pass Modern argument of type Fixnum to parameter "value" of type String in call "target"',
        ],
      }

      cases.each do |description, (source, column, message)|
        source_path = File.join(directory, "#{description}.dabm")
        File.binwrite(source_path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          source_path,
          "--ring-base[]=#{lower}"
        )

        expect([status.exitstatus, stdout]).to eq([2, '']), description
        expect(tool_stderr(stderr)).to eq(
          "compiler: #{source_path}:2:#{column}: error: #{message}\n"
        ), description
      end
    end
  end

  it 'retains Ring signatures and emits only existing call and syscall assembly' do
    Dir.mktmpdir('dab-modern-call-assembly') do |directory|
      lower = build_stdlib(directory)
      lower_unit, = DabBinReader.new.parse_ring(lower, [])
      signature = lower_unit.has_function?('puts').ring_signature
      expect(signature).to eq(puts_signature)
      expect(signature[:return_type]).to be_frozen
      expect(signature[:arguments].first.values).to all(be_frozen)
      expect do
        signature[:arguments].first[:type].replace('String')
      end.to raise_error(FrozenError)
      expect do
        parse("def main\nmissing()\nend\n").lower_into(lower_unit)
      end.to raise_error(DabModernBootstrapParseError, 'unknown Modern call target "missing"')
      expect(lower_unit.has_function?('import_libc')).to be_truthy
      expect do
        parse("def main\nimport_libc(nil)\nend\n").lower_into(lower_unit)
      end.to raise_error(
        DabModernBootstrapParseError,
        'unsupported Modern call target "import_libc" in the R39 ordinary-call subset'
      )
      expect(lower_unit.classes.to_a.flat_map { |klass| klass.functions.to_a }.map(&:identifier)).to include('to_s')
      expect do
        parse("def main\nto_s()\nend\n").lower_into(lower_unit)
      end.to raise_error(
        DabModernBootstrapParseError,
        'unsupported Modern call target "to_s" in the R39 ordinary-call subset'
      )

      source_path = File.join(directory, 'calls.dabm')
      File.binwrite(
        source_path,
        <<~DAB
          def main
          helper(1,"H",true)
          print()
          print(nil,true,1,"M")
          print("P")
          puts("Q")
          ready?()
          save!()
          end
          def helper(first:Fixnum,second:String,third:Boolean)
          end
          def ready?
          end
          def save!
          end
          def recurse
          recurse()
          end
        DAB
      )
      assembly = compile(source_path, lower)

      expect(assembly).to match(%r{/\* helper\s+\*/\s+CALL RNIL,})
      expect(assembly).to match(%r{/\* PRINT\s+\*/\s+SYSCALL RNIL, 0,})
      print_syscalls = assembly.lines.grep(%r{/\* PRINT\s+\*/})
      expect(print_syscalls.length).to eq(5)
      expect(print_syscalls).to all(match(/SYSCALL RNIL, 0, R\d+\n\z/))
      expect(assembly).to match(%r{/\* puts\s+\*/\s+CALL RNIL,})
      expect(assembly).to match(%r{/\* ready\?\s+\*/\s+CALL RNIL,})
      expect(assembly).to match(%r{/\* save!\s+\*/\s+CALL RNIL,})
      expect(assembly).to match(%r{Frecurse:.*?/\* recurse\s+\*/\s+CALL RNIL,}m)
      expect(assembly).to include('Fready%QUEST:', 'Fsave%BANG:', 'RETURN RNIL')
      expect(assembly).not_to match(/CALL R\d/)
      expect(assembly.index('LOAD_NUMBER')).to be < assembly.index('LOAD_STRING')
      expect(assembly.index('LOAD_STRING')).to be < assembly.index('LOAD_TRUE')
      expect(assembly.index('LOAD_TRUE')).to be < assembly.index('/* helper')
    end
  end

  it 'executes same-document, print, and puts calls while discarding every result', :native do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-call-runtime') do |directory|
      lower = build_stdlib(directory)
      source_path = File.join(directory, 'calls.dabm')
      File.binwrite(
        source_path,
        <<~DAB
          def main
          emit()
          puts("B")
          end
          def emit
          print("A")
          end
        DAB
      )
      assembly = compile(source_path, lower)
      bytecode, assembler_stderr, assembler_status = invoke(RbConfig.ruby, assembler, input: assembly)
      expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq([0, ''])

      upper = File.join(directory, 'calls.dabcb')
      application_output = File.join(directory, 'application.stdout')
      File.binwrite(upper, bytecode)
      stdout, stderr, status = invoke(
        vm,
        '--entry=main',
        "--out=#{application_output}",
        lower,
        upper
      )

      expect([status.exitstatus, stdout, File.binread(application_output)]).to eq([0, '', "AB\n"])
      expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
    end
  end
end
