require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern bootstrap literals' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:source_unit) do
    DabSourceUnit.new(input: 'literals.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
  let(:literal_source) do
    "def main\nnil;true// bool separator\nfalse;0;01;9223372036854775807\nend\n".b
  end

  def parse_modern(source)
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

  def compile(path, lower)
    assembly, stderr, status = invoke(RbConfig.ruby, compiler, path, "--ring-base[]=#{lower}")
    expect([status.exitstatus, tool_stderr(stderr)]).to eq [0, '']
    assembly
  end

  it 'characterizes the reused Legacy literal parser and AST values' do
    source = 'func main(){nil;true;false;0;01;42;9223372036854775807;}'
    unit = DabCompiler.new(DabProgramStream.new(source, true, 'legacy-literals.dab')).program
    body = unit.has_function?('main').blocks[0]

    expect(unit.errors).to be_empty
    expect(body.map(&:class)).to eq(
      [
        DabNodeLiteralNil,
        DabNodeLiteralBoolean,
        DabNodeLiteralBoolean,
        DabNodeLiteralNumber,
        DabNodeLiteralNumber,
        DabNodeLiteralNumber,
        DabNodeLiteralNumber,
      ]
    )
    expect(body.map(&:constant_value)).to eq([nil, true, false, 0, 1, 42, 9_223_372_036_854_775_807])
  end

  it 'scans exact lowercase literal tokens with half-open source spans' do
    scanner = DabModernBootstrapScanner.new(literal_source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end
    literals = tokens.select { |token| %i[nil boolean_true boolean_false integer].include?(token.kind) }

    expect(literals.map { |token| [token.kind, token.text] }).to eq(
      [
        [:nil, 'nil'],
        [:boolean_true, 'true'],
        [:boolean_false, 'false'],
        [:integer, '0'],
        [:integer, '01'],
        [:integer, '9223372036854775807'],
      ]
    )
    expect(literals.map { |token| [token.source_span.start_offset, token.source_span.end_offset] }).to eq(
      [[9, 12], [13, 17], [35, 40], [41, 42], [43, 45], [46, 65]]
    )
    expect(literals.map { |token| token.source_location.to_h }).to eq(
      [
        {offset: 9, line: 2, column: 0},
        {offset: 13, line: 2, column: 4},
        {offset: 35, line: 3, column: 0},
        {offset: 41, line: 3, column: 6},
        {offset: 43, line: 3, column: 8},
        {offset: 46, line: 3, column: 11},
      ]
    )
    expect(literals).to all(satisfy { |token| token.source_span.source_unit.equal?(source_unit) })
  end

  it 'lowers literals through the existing Legacy AST nodes with their source spans' do
    declaration = parse_modern(literal_source)
    unit = DabNodeUnit.new
    body = declaration.lower_into(unit).blocks[0]

    expect(declaration.body_tokens.map(&:kind)).to eq(
      %i[nil boolean_true boolean_false integer integer integer]
    )
    expect(body.map(&:class)).to eq(
      [
        DabNodeLiteralNil,
        DabNodeLiteralBoolean,
        DabNodeLiteralBoolean,
        DabNodeLiteralNumber,
        DabNodeLiteralNumber,
        DabNodeLiteralNumber,
      ]
    )
    expect(body.map(&:constant_value)).to eq([nil, true, false, 0, 1, 9_223_372_036_854_775_807])
    expect(body.map { |node| [node.source_cstart, node.source_cend] }).to eq(
      [[9, 12], [13, 17], [35, 40], [41, 42], [43, 45], [46, 65]]
    )
  end

  it 'reuses the established literal assembly instructions without a new runtime representation' do
    unit = DabNodeUnit.new
    body = parse_modern("def main\nnil\ntrue\nfalse\n9223372036854775807\nend\n").lower_into(unit).blocks[0]
    output = spy('assembly output')

    body.each_with_index { |node, register| node.compile_as_ssa(output, register) }

    expect(output).to have_received(:printex).with(body[0], 'LOAD_NIL', 'R0')
    expect(output).to have_received(:printex).with(body[1], 'LOAD_TRUE', 'R1')
    expect(output).to have_received(:printex).with(body[2], 'LOAD_FALSE', 'R2')
    expect(output).to have_received(:comment).with('9223372036854775807')
    expect(output).to have_received(:print).with('LOAD_NUMBER', 'R3', '9223372036854775807')
  end

  it 'accepts literals with every established separator and comment interaction' do
    sources = [
      "def main\nnil\ntrue\nfalse\n0\nend\n",
      'def main;nil;true;false;0;end;',
      "# lead\ndef main// header\nnil# nil\ntrue// true\nfalse;# false\n0// zero\nend# tail",
    ]

    sources.each do |source|
      expect(parse_modern(source).body_tokens.map(&:kind)).to eq(%i[nil boolean_true boolean_false integer])
    end
  end

  it 'rejects non-literals, unsupported literal families, signs, operators, and malformed numbers exactly' do
    cases = {
      'nil spelling' => ["def main\nNil\nend\n", 9],
      'null spelling' => ["def main\nnull\nend\n", 9],
      'true spelling' => ["def main\nTrue\nend\n", 9],
      'false spelling' => ["def main\nFALSE\nend\n", 9],
      'positive sign' => ["def main\n+1\nend\n", 9],
      'negative sign' => ["def main\n-1\nend\n", 9],
      'float' => ["def main\n1.0\nend\n", 10],
      'binary number' => ["def main\n0b1\nend\n", 10],
      'numeric underscore' => ["def main\n1_0\nend\n", 10],
      'integer overflow' => ["def main\n9223372036854775808\nend\n", 9],
      'binary operator' => ["def main\n1+2\nend\n", 10],
      'binding' => ["def main\nlet value = 1\nend\n", 9],
      'call' => ["def main\nvalue()\nend\n", 9],
      'return' => ["def main\nreturn 1\nend\n", 9],
      'control flow' => ["def main\nif true\nend\nend\n", 9],
      'second declaration' => ["def main\nnil\nend\ndef main\nend\n", 17],
    }

    cases.each do |description, (source, offset)|
      expect do
        parse_modern(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq 'unsupported Dab syntax profile "modern": parser is not implemented'
        expect(error.source_location.offset).to eq(offset), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'fails the compiler transactionally at the overflowing literal location' do
    Dir.mktmpdir('dab-modern-literal-overflow') do |directory|
      lower = File.join(directory, 'stdlib.dabcb')
      stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{lower}")
      expect([status.exitstatus, stdout]).to eq [0, "PASS #{lower}\n"]
      expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')

      path = File.join(directory, 'overflow.dabm')
      File.binwrite(path, "def main\nnil\n9223372036854775808\nend\n")
      output, compiler_stderr, compiler_status = invoke(
        RbConfig.ruby,
        compiler,
        path,
        "--ring-base[]=#{lower}"
      )

      expect(compiler_status.exitstatus).to eq 2
      expect(output).to eq ''
      expect(tool_stderr(compiler_stderr)).to eq(
        "compiler: #{path}:3:0: error: unsupported Dab syntax profile \"modern\": parser is not implemented\n"
      )
    end
  end

  it 'matches equivalent Legacy assembly and executes deterministic upper Rings through the existing stdlib' do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-literals') do |directory|
      lower = File.join(directory, 'stdlib.dabcb')
      stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{lower}")
      expect([status.exitstatus, stdout]).to eq [0, "PASS #{lower}\n"]
      expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')

      modern = File.join(directory, 'literals.dabm')
      legacy = File.join(directory, 'literals.dab')
      empty = File.join(directory, 'empty.dabm')
      File.binwrite(modern, "def main\nnil\ntrue\nfalse\n0\n01\n9223372036854775807\nend\n")
      File.binwrite(legacy, 'func main(){nil;true;false;0;01;9223372036854775807;}')
      File.binwrite(empty, "def main\nend\n")

      modern_assemblies = Array.new(2) { compile(modern, lower) }
      legacy_assembly = compile(legacy, lower)
      empty_assembly = compile(empty, lower)
      expect(modern_assemblies.uniq).to eq [legacy_assembly]
      expect(modern_assemblies.first).to eq empty_assembly
      expect(modern_assemblies.first).not_to include('LOAD_NIL', 'LOAD_TRUE', 'LOAD_FALSE', 'LOAD_NUMBER')

      bytecodes = modern_assemblies.map do |assembly|
        bytecode, assembler_stderr, assembler_status = invoke(RbConfig.ruby, assembler, input: assembly)
        expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq [0, '']
        bytecode
      end
      expect(bytecodes.uniq.length).to eq 1

      upper = File.join(directory, 'literals.dabcb')
      File.binwrite(upper, bytecodes.first)
      application_stdout = File.join(directory, 'application.stdout')
      process_stdout, host_stderr, vm_status = invoke(vm, "--out=#{application_stdout}", lower, upper)

      expect([vm_status.exitstatus, process_stdout, File.binread(application_stdout)]).to eq [0, '', '']
      expect(host_stderr).to include('vm: add function <main>.', 'vm: VM destroyed!')
      expect(host_stderr).not_to match(/error|failed|sanitizer|warning/i)
    end
  end
end
