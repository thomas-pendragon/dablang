require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern typed parameters and return contracts' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:cdisasm) { File.join(root, "bin/cdisasm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'typed-parameters.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def invoke(*command, input: nil)
    Open3.capture3(*command, stdin_data: input, chdir: root)
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
    expect(stderr).not_to include('exception:', 'FAILED')
    artifact
  end

  it 'scans typed-header punctuation and horizontal whitespace with exact byte spans' do
    scanner = DabModernBootstrapScanner.new("\t(),:".b, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end

    expect(tokens.map { |token| [token.kind, token.text] }).to eq(
      [
        [:tab, "\t"],
        [:left_parenthesis, '('],
        [:right_parenthesis, ')'],
        [:comma, ','],
        [:colon, ':'],
        [:eof, ''],
      ]
    )
    expect(tokens.map { |token| [token.source_span.start_offset, token.source_span.end_offset] }).to eq(
      [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 5]]
    )
  end

  it 'accepts bare and explicit-empty zero-parameter declarations' do
    sources = {
      'bare' => ["def bare\nend\n", 'Object'],
      'empty' => ["def empty()\nend\n", 'Object'],
      'spaced' => ["def spaced \t ( \t ) \t\nend\n", 'Object'],
      'trailing' => ["def trailing \t;end\n", 'Object'],
      'returning' => ["def returning \t: \tFloat\nend\n", 'Float'],
    }

    functions = sources.map do |_name, (source, return_type)|
      document = parse(source)
      declaration = document.declarations.fetch(0)
      function = document.lower_into(DabNodeUnit.new)
      expect(declaration.parameters).to be_empty
      expect(declaration.return_type&.text).to eq(return_type == 'Object' ? nil : return_type)
      function
    end

    expect(functions.map(&:identifier)).to eq(sources.keys)
    expect(functions).to all(satisfy { |function| function.arglist.empty? })
    expect(functions.map { |function| function.return_type.type_string }).to eq(
      sources.values.map(&:last)
    )
  end

  it 'retains ordered parameter, type, return, and source metadata through lowering' do
    source = "def typed\t(\tfirst:Int32 , second : String\t)\t:\tBoolean\nnil\nend\n"
    document = parse(source)
    declaration = document.declarations.fetch(0)

    expect(declaration.parameters.map { |parameter| [parameter.name, parameter.type_name.text] }).to eq(
      [%w[first Int32], %w[second String]]
    )
    expect(declaration.parameters.map { |parameter| [parameter.source_span.start_offset, parameter.source_span.end_offset] })
      .to eq(
        [
          [source.index('first'), source.index('Int32') + 'Int32'.length],
          [source.index('second'), source.index('String') + 'String'.length],
        ]
      )
    expect(declaration.return_type.text).to eq('Boolean')

    function = document.lower_into(DabNodeUnit.new)
    expect(function.arglist.map { |argument| [argument.index, argument.identifier, argument.my_type.type_string] }).to eq(
      [[0, 'first', 'Int32'], [1, 'second', 'String']]
    )
    expect(function.arglist.map { |argument| [argument.source_cstart, argument.source_cend] }).to eq(
      declaration.parameters.map { |parameter| [parameter.source_span.start_offset, parameter.source_span.end_offset] }
    )
    expect(function.return_type.type_string).to eq('Boolean')
    expect(function.blocks[0].all_nodes(DabNodeLiteralNil)).not_to be_empty
  end

  it 'accepts exactly the fourteen closed type spellings' do
    type_names = DabModernBootstrapParser::SUPPORTED_TYPE_NAMES
    parameters = type_names.each_with_index.map { |type_name, index| "a#{index}:#{type_name}" }.join(',')
    document = parse("def all(#{parameters}):Float\nend\n")
    function = document.lower_into(DabNodeUnit.new)

    expect(function.arglist.map { |argument| argument.my_type.type_string }).to eq(type_names)
    expect(function.return_type.type_string).to eq('Float')
  end

  it 'uses all nine contextual diagnostic families with first-unmet-production spans' do
    unknown_message =
      'unknown Modern type "Object"; supported types are String, Fixnum, Boolean, Uint8, Uint16, ' \
      'Uint32, Uint64, Int8, Int16, Int32, Int64, IntPtr, NilClass, and Float'
    cases = {
      'parameter-or-close' => ["def f(,\n", DabModernBootstrapParser::EXPECT_PARAMETER_OR_CLOSE_MESSAGE, [6, 7]],
      'parameter-colon' => ["def f(a)\n", DabModernBootstrapParser::EXPECT_PARAMETER_COLON_MESSAGE, [7, 8]],
      'parameter-type' => ["def f(a:)\n", DabModernBootstrapParser::EXPECT_PARAMETER_TYPE_MESSAGE, [8, 9]],
      'parameter-separator' => [
        "def f(a:Int32 b:String)\n",
        DabModernBootstrapParser::EXPECT_PARAMETER_SEPARATOR_MESSAGE,
        [14, 15],
      ],
      'parameter-after-comma' => [
        "def f(a:Int32,)\n",
        DabModernBootstrapParser::EXPECT_PARAMETER_AFTER_COMMA_MESSAGE,
        [14, 15],
      ],
      'parameter-close' => ['def f(', DabModernBootstrapParser::EXPECT_PARAMETER_CLOSE_MESSAGE, [6, 6]],
      'return-type' => ['def f:', DabModernBootstrapParser::EXPECT_RETURN_TYPE_MESSAGE, [6, 6]],
      'unknown-type' => ["def f(a:Object)\n", unknown_message, [8, 14]],
      'duplicate' => ["def f(a:Int32,a:String)\n", 'duplicate Modern parameter "a"', [14, 15]],
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

  it 'rejects excluded type and grammar forms without consuming later rows' do
    cases = {
      'ByteBuffer' => ["def f(a:ByteBuffer)\nend\n", /unknown Modern type "ByteBuffer"/],
      'future Bool alias' => ["def f(a:Bool)\nend\n", /unknown Modern type "Bool"/],
      'default' => ["def f(a:Int32=1)\nend\n", /expected "," or closing "\)"/],
      'generic' => ["def f(a:Array[String])\nend\n", /unknown Modern type "Array"/],
      'variadic' => ["def f(*a:Int32)\nend\n", /expected a parameter name or closing "\)"/],
      'body reference' => ["def f(a:Int32)\na\nend\n", /parser is not implemented/],
      'call' => ["def f(a:Int32)\nvalue()\nend\n", /parser is not implemented/],
    }

    cases.each do |description, (source, message)|
      expect { parse(source) }.to raise_error(DabModernBootstrapParseError, message), description
    end
  end

  it 'preserves CR and CRLF rejection throughout the typed header' do
    ["def f(a:Int32\r)\nend\n", "def f(a:Int32\r\n)\nend\n"].each do |source|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE)
        expect(error.source_span.end_offset - error.source_span.start_offset).to eq(source.include?("\r\n") ? 2 : 1)
      }
    end
  end

  it 'keeps callable uniqueness independent of typed arity and leaves the unit untouched' do
    document = parse("def same(a:Int32)\nend\ndef same(a:String,b:Boolean)\nend\n")
    unit = DabNodeUnit.new

    expect do
      document.lower_into(unit)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([26, 30])
    }
    expect(unit.functions).to be_empty
  end

  it 'reports invalid signatures before attempting to load a lower Ring' do
    Dir.mktmpdir('dab-modern-typed-preflight') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      File.binwrite(source_path, "def valid(value:Int32)\nend\ndef main(value:Object)\nend\n")
      missing_ring = File.join(directory, 'missing.dabcb')

      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:3:15: error: " \
        'unknown Modern type "Object"; supported types are String, Fixnum, Boolean, Uint8, Uint16, ' \
        "Uint32, Uint64, Int8, Int16, Int32, Int64, IntPtr, NilClass, and Float\n"
      )
      expect(File).not_to exist(missing_ring)
    end
  end

  it 'preserves typed signature metadata through assembly, bytecode, and native loading', :native do
    expect(File).to exist(vm)
    expect(File).to exist(cdisasm)

    source = "def main()\nend\ndef typed(first:Int32, second:String):Boolean\nend\n"
    Dir.mktmpdir('dab-modern-typed-metadata') do |directory|
      lower = build_stdlib(directory)
      source_path = File.join(directory, 'typed.dabm')
      File.binwrite(source_path, source)
      assembly, compiler_stderr, compiler_status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{lower}"
      )

      expect([compiler_status.exitstatus, tool_stderr(compiler_stderr)]).to eq([0, ''])
      expect(assembly).to match(%r{W_METHOD \d+, -1, Ftyped, 2,})
      expect(assembly).to match(%r{/\* first<Int32>\s+\*/\s+W_METHOD_ARG \d+, 12})
      expect(assembly).to match(%r{/\* second<Strin \*/\s+W_METHOD_ARG \d+, 1})
      expect(assembly).to match(%r{/\* \$ret<Boolean \*/\s+W_METHOD_ARG -1, 3})

      bytecode, assembler_stderr, assembler_status = invoke(RbConfig.ruby, assembler, input: assembly)
      expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq([0, ''])

      disassembly, disassembler_stderr, disassembler_status = invoke(
        cdisasm,
        '--with-headers',
        '--no-numbers',
        input: bytecode
      )
      expect(disassembler_status.exitstatus).to eq(0)
      expect(disassembler_stderr).not_to match(/error|invalid|failed/i)
      expect(disassembly).to match(
        /W_METHOD \d+, -1, \d+, 2, \d+, 0\n\s+W_METHOD_ARG \d+, 12\n\s+W_METHOD_ARG \d+, 1\n\s+W_METHOD_ARG -1, 3/
      )

      upper = File.join(directory, 'typed.dabcb')
      output = File.join(directory, 'typed.out')
      File.binwrite(upper, bytecode)
      vm_stdout, vm_stderr, vm_status = invoke(
        vm,
        '--verbose',
        '--entry=main',
        "--out=#{output}",
        lower,
        upper
      )
      expect([vm_status.exitstatus, vm_stdout, File.binread(output)]).to eq([0, '', ''])
      expect(vm_stderr).to match(/func \d+: 'typed'.*with 2 args/)
    end
  end
end
