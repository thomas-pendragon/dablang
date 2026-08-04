require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'
require_relative '../src/compiler/parts/output'

describe 'Modern bootstrap String literals' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:decompiler) { File.join(root, 'src/decompile/decompile.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(input: 'strings.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
  let(:string_source) do
    "def main\n\"\";\"plain\";\"Zażółć 🐉\";\"quote: \\\"\";\"line\\nfeed\";\"carriage\\rreturn\"\nend\n".b
  end

  def parse_modern(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def scan(source)
    scanner = DabModernBootstrapScanner.new(source.b, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof || token.kind == :unsupported
    end
    tokens
  end

  def invoke(*command, input: nil, binmode: false)
    Open3.capture3(*command, stdin_data: input, binmode: binmode, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def compile(path, lower)
    assembly, stderr, status = invoke(RbConfig.ruby, compiler, path, "--ring-base[]=#{lower}")
    expect([status.exitstatus, tool_stderr(stderr)]).to eq [0, '']
    assembly
  end

  it 'preserves the characterized permissive Legacy String parser byte-for-byte' do
    source = "func main(){\"\";\"plain\";\"line\\nfeed\";\"carriage\\rreturn\";\"literal \#{marker}\";\"unknown\\q\";\"raw \xFF\";\"nul \0 byte\";}".b
    unit = DabCompiler.new(DabProgramStream.new(source, true, 'legacy-strings.dab')).program
    strings = unit.has_function?('main').blocks[0]

    expect(unit.errors).to be_empty
    expect(strings.map(&:class)).to all(eq(DabNodeLiteralString))
    expect(strings.map(&:constant_value)).to eq(
      [
        ''.b,
        'plain'.b,
        "line\nfeed".b,
        "carriage\rreturn".b,
        "literal \#{marker}".b,
        'unknown\q'.b,
        "raw \xFF".b,
        "nul \0 byte".b,
      ]
    )
  end

  it 'scans empty, plain UTF-8, and exactly the three accepted escapes with delimiter spans' do
    strings = scan(string_source).select { |token| token.kind == :string }

    expect(strings.map(&:text)).to eq(
      [
        '""'.b,
        '"plain"'.b,
        '"Zażółć 🐉"'.b,
        '"quote: \""'.b,
        '"line\nfeed"'.b,
        '"carriage\rreturn"'.b,
      ]
    )
    expect(strings.map(&:value)).to eq(
      [
        ''.b,
        'plain'.b,
        'Zażółć 🐉'.b,
        'quote: "'.b,
        "line\nfeed".b,
        "carriage\rreturn".b,
      ]
    )
    expect(strings.map { |token| [token.source_span.start_offset, token.source_span.end_offset] }).to eq(
      [[9, 11], [12, 19], [20, 37], [38, 49], [50, 62], [63, 81]]
    )
    expect(strings.map { |token| token.source_location.to_h }).to eq(
      [
        {offset: 9, line: 2, column: 0},
        {offset: 12, line: 2, column: 3},
        {offset: 20, line: 2, column: 11},
        {offset: 38, line: 2, column: 29},
        {offset: 50, line: 2, column: 41},
        {offset: 63, line: 2, column: 54},
      ]
    )
    expect(strings).to all(satisfy { |token| token.value.encoding == Encoding::BINARY })
    expect(strings).to all(satisfy { |token| token.source_span.source_unit.equal?(source_unit) })
  end

  it 'normalizes text-mode Modern input to byte offsets before scanning' do
    source = "def main\n\"Zażółć 🐉\"\n+\nend\n"
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    token = nil
    token = scanner.next_token until token&.kind == :unsupported

    expect(scanner.content.encoding).to eq(Encoding::BINARY)
    expect(token.text).to eq('+'.b)
    expect(token.source_location.offset).to eq(source.b.index('+'))
  end

  it 'lowers every accepted String through DabNodeLiteralString with the full delimiter span' do
    declaration = parse_modern(string_source)
    unit = DabNodeUnit.new
    body = declaration.lower_into(unit).blocks[0]

    expect(declaration.body_tokens.map(&:kind)).to eq([:string] * 6)
    expect(body.map(&:class)).to eq([DabNodeLiteralString] * 6)
    expect(body.map(&:constant_value)).to eq(
      ['', 'plain', 'Zażółć 🐉', 'quote: "', "line\nfeed", "carriage\rreturn"].map(&:b)
    )
    expect(body.map { |node| [node.source_cstart, node.source_cend] }).to eq(
      [[9, 11], [12, 19], [20, 37], [38, 49], [50, 62], [63, 81]]
    )
  end

  it 'represents embedded quotes without changing existing trailing-backslash assembly' do
    stdout = StringIO.new
    output = DabOutput.new(double(stdout: stdout))
    quote = DabNodeLiteralString.new('quote: "'.b)
    trailing_backslash = DabNodeLiteralString.new('ends \\'.b)

    quote.compile_constant(output)
    quote.compile_string(output)
    trailing_backslash.compile_string(output)

    expect(stdout.string).to include('CONSTANT_STRING "quote: """')
    expect(stdout.string).to include('W_STRING "quote: """')
    expect(stdout.string).to include('W_STRING "ends \\"')

    quote_raw, quote_stderr, quote_status = invoke(
      RbConfig.ruby,
      assembler,
      '--raw',
      input: "W_STRING \"quote: \"\"\"\n"
    )
    expect([quote_status.exitstatus, tool_stderr(quote_stderr), quote_raw.b]).to eq(
      [0, '', "quote: \"\0".b]
    )

    backslash_raw, backslash_stderr, backslash_status = invoke(
      RbConfig.ruby,
      assembler,
      '--raw',
      input: "W_STRING \"ends \\\"\n"
    )
    expect([backslash_status.exitstatus, tool_stderr(backslash_stderr), backslash_raw.b]).to eq(
      [0, '', "ends \\\0".b]
    )
  end

  it 'renders formatter and decompiler Strings with stable R35 escapes' do
    values = [
      'quote: "'.b,
      "carriage\rreturn".b,
      "line\nfeed".b,
      "adjacent\"\r\nend".b,
    ]

    values.each do |value|
      rendered = DabNodeLiteralString.new(value).formatted_source({})
      declaration = parse_modern("def main\n#{rendered}\nend\n".b)
      body = declaration.lower_into(DabNodeUnit.new).blocks[0]

      expect(body.map(&:constant_value)).to eq([value])
    end

    expect(DabNodeLiteralString.new('raw \\ and \\n \\r'.b).formatted_source({})).to eq(
      '"raw \\ and \\n \\r"'.b
    )
  end

  it 'escapes quote and line controls in decompiled bytecode Strings' do
    Dir.mktmpdir('dab-modern-string-decompile') do |directory|
      source = File.join(directory, 'string.dab')
      File.binwrite(source, 'func main(){return "abcde";}')
      assembly, compiler_stderr, compiler_status = invoke(RbConfig.ruby, compiler, source)
      expect([compiler_status.exitstatus, tool_stderr(compiler_stderr)]).to eq [0, '']
      assembly = assembly.sub('W_STRING "abcde"', 'W_STRING "q""\\r\\nx"')

      bytecode, assembler_stderr, assembler_status = invoke(
        RbConfig.ruby,
        '-e',
        'STDOUT.binmode; load ARGV.shift',
        assembler,
        input: assembly,
        binmode: true
      )
      expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq [0, '']

      decompiled, decompiler_stderr, decompiler_status = invoke(
        RbConfig.ruby,
        decompiler,
        input: bytecode,
        binmode: true
      )
      expect(decompiler_status.exitstatus).to eq(0), decompiler_stderr
      expect(decompiled).to include('return "q\\"\\r\\nx";')
    end
  end

  it 'forwards the assembly-only doubled-quote option through parser contexts' do
    context = DabBaseContext.new(DabParser.new('"quote: """'))

    expect(context.read_string(true)).to eq('quote: "')
  end

  it 'rejects invalid bytes, NUL, physical newlines, unterminated text, unknown escapes, and interpolation at the marker' do
    supported_escapes = 'supported escapes are \", \\n, and \\r'
    cases = {
      'invalid UTF-8 lead' => [
        "def main\n\"ok \xC3(\"\nend\n".b,
        13,
        'invalid UTF-8 byte 0xC3 in Modern String literal',
      ],
      'invalid UTF-8 continuation' => [
        "def main\n\"ok \x80\"\nend\n".b,
        13,
        'invalid UTF-8 byte 0x80 in Modern String literal',
      ],
      'overlong UTF-8' => [
        "def main\n\"ok \xC0\xAF\"\nend\n".b,
        13,
        'invalid UTF-8 byte 0xC0 in Modern String literal',
      ],
      'UTF-8 surrogate' => [
        "def main\n\"ok \xED\xA0\x80\"\nend\n".b,
        13,
        'invalid UTF-8 byte 0xED in Modern String literal',
      ],
      'UTF-8 above Unicode range' => [
        "def main\n\"ok \xF4\x90\x80\x80\"\nend\n".b,
        13,
        'invalid UTF-8 byte 0xF4 in Modern String literal',
      ],
      'truncated UTF-8 sequence' => [
        "def main\n\"ok \xE2".b,
        13,
        'invalid UTF-8 byte 0xE2 in Modern String literal',
      ],
      'NUL' => [
        "def main\n\"a\0b\"\nend\n".b,
        11,
        'invalid Modern String literal: NUL is not allowed',
      ],
      'literal LF' => [
        "def main\n\"a\nb\"\nend\n".b,
        11,
        'invalid Modern String literal: literal LF is not allowed; use "\\n"',
      ],
      'literal CR' => [
        "def main\n\"a\rb\"\nend\n".b,
        11,
        'invalid Modern String literal: literal CR is not allowed; use "\\r"',
      ],
      'unterminated' => [
        "def main\n\"text".b,
        14,
        'unterminated Modern String literal',
      ],
      'unterminated escape' => [
        "def main\n\"text\\".b,
        14,
        'unterminated Modern String literal escape',
      ],
      'unknown escape' => [
        "def main\n\"a\\tb\"\nend\n".b,
        11,
        "invalid Modern String literal escape \"\\\\t\"; #{supported_escapes}",
      ],
      'doubled backslash' => [
        "def main\n\"a\\\\b\"\nend\n".b,
        11,
        "invalid Modern String literal escape \"\\\\\\\\\"; #{supported_escapes}",
      ],
      'reserved interpolation' => [
        "def main\n\"a\#{value}\"\nend\n".b,
        11,
        'invalid Modern String literal: interpolation marker "#{" is reserved',
      ],
    }

    cases.each do |description, (source, offset, message)|
      token = scan(source).last
      expect(token.kind).to eq(:unsupported), description
      expect(token.source_span.start_offset).to eq(offset), description
      expect(token.source_location.offset).to eq(offset), description
      expect(token.diagnostic_message).to eq(message), description

      expect do
        parse_modern(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(error.source_location.offset).to eq(offset), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'keeps adjacent Strings, single quotes, and later expression syntax fail-closed' do
    cases = {
      'adjacent literals' => ["def main\n\"a\"\"b\"\nend\n", 12],
      'single quotes' => ["def main\n'a'\nend\n", 9],
      'String operator' => ["def main\n\"a\"+\"b\"\nend\n", 12],
      'String binding' => ["def main\nlet value = \"a\"\nend\n", 9],
      'String call argument' => ["def main\nprint(\"a\")\nend\n", 9],
      'String return' => ["def main\nreturn \"a\"\nend\n", 9],
    }

    cases.each do |description, (source, offset)|
      expect do
        parse_modern(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(error.source_location.offset).to eq(offset), description
      }
    end
  end

  it 'fails compilation transactionally and leaves the lower Ring reusable' do
    Dir.mktmpdir('dab-modern-invalid-string') do |directory|
      lower = File.join(directory, 'stdlib.dabcb')
      stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{lower}")
      expect([status.exitstatus, stdout]).to eq [0, "PASS #{lower}\n"]
      expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')
      lower_before = File.binread(lower)

      invalid = File.join(directory, 'invalid.dabm')
      File.binwrite(invalid, "def main\n\"reserved \#{value}\"\nend\n")
      output, compiler_stderr, compiler_status = invoke(
        RbConfig.ruby,
        compiler,
        invalid,
        "--ring-base[]=#{lower}"
      )

      expect([compiler_status.exitstatus, output]).to eq [2, '']
      expect(tool_stderr(compiler_stderr)).to eq(
        "compiler: #{invalid}:2:10: error: " \
        "invalid Modern String literal: interpolation marker \"\#{\" is reserved\n"
      )
      expect(File.binread(lower)).to eq(lower_before)

      valid = File.join(directory, 'valid.dabm')
      File.binwrite(valid, "def main\n\"plain\"\nend\n")
      expect(compile(valid, lower)).not_to be_empty
      expect(File.binread(lower)).to eq(lower_before)
    end
  end

  it 'matches equivalent Legacy assembly, bytecode, and runtime behavior' do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-strings') do |directory|
      lower = File.join(directory, 'stdlib.dabcb')
      stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{lower}")
      expect([status.exitstatus, stdout]).to eq [0, "PASS #{lower}\n"]
      expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')

      modern = File.join(directory, 'strings.dabm')
      legacy = File.join(directory, 'strings.dab')
      File.binwrite(modern, "def main\n\"\"\n\"plain\"\n\"Zażółć 🐉\"\n\"line\\nfeed\"\n\"carriage\\rreturn\"\nend\n")
      File.binwrite(legacy, 'func main(){"";"plain";"Zażółć 🐉";"line\nfeed";"carriage\rreturn";}'.b)

      modern_assemblies = Array.new(2) { compile(modern, lower) }
      legacy_assembly = compile(legacy, lower)
      expect(modern_assemblies.uniq).to eq [legacy_assembly]

      bytecodes = modern_assemblies.map do |assembly|
        bytecode, assembler_stderr, assembler_status = invoke(RbConfig.ruby, assembler, input: assembly)
        expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq [0, '']
        bytecode
      end
      expect(bytecodes.uniq.length).to eq 1

      upper = File.join(directory, 'strings.dabcb')
      File.binwrite(upper, bytecodes.first)
      application_stdout = File.join(directory, 'application.stdout')
      process_stdout, host_stderr, vm_status = invoke(vm, "--out=#{application_stdout}", lower, upper)

      expect([vm_status.exitstatus, process_stdout, File.binread(application_stdout)]).to eq [0, '', '']
      expect(host_stderr).to include('vm: add function <main>.', 'vm: VM destroyed!')
      expect(host_stderr).not_to match(/error|failed|sanitizer|warning/i)
    end
  end
end
