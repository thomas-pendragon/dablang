require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

RegexRuntimeResult = Struct.new(:stdout, :stderr, :status, keyword_init: true)

describe 'Regex runtime object and engine contract' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:vm) do
    ENV.fetch(
      'DAB_REGEX_RUNTIME_VM',
      File.join(root, 'bin', "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}")
    )
  end

  def invoke_binary_ruby(script, stdin_data: '')
    Open3.capture3(
      RbConfig.ruby, '-e', 'STDOUT.binmode; load ARGV.shift', script,
      stdin_data: stdin_data, binmode: true, chdir: root
    )
  end

  def compile(source)
    Dir.mktmpdir('dab-regex-runtime-spec') do |directory|
      source_path = File.join(directory, 'program.dab')
      bytecode_path = File.join(directory, 'program.dabcb')
      File.binwrite(source_path, source.b)
      assembly, compiler_error, compiler_status = Open3.capture3(
        RbConfig.ruby, File.join(root, 'src/compiler/compiler.rb'), source_path, chdir: root
      )
      expect(compiler_status.exitstatus).to eq(0), compiler_error
      bytecode, assembler_error, assembler_status = invoke_binary_ruby(
        File.join(root, 'src/tobinary/tobinary.rb'), stdin_data: assembly
      )
      expect(assembler_status.exitstatus).to eq(0), assembler_error
      File.binwrite(bytecode_path, bytecode)
      yield bytecode_path
    end
  end

  def execute(source, environment = {})
    compile(source) do |bytecode|
      stdout, stderr, status = Open3.capture3(
        environment, vm, bytecode, chdir: root, binmode: true
      )
      return RegexRuntimeResult.new(stdout: stdout.b, stderr: stderr.b, status: status.exitstatus)
    end
  end

  def main(body)
    "func main()\n{\n#{body}\n}\n".b
  end

  def constructor(pattern)
    %(\tRegex.new("#{pattern}");)
  end

  def constructor_bytes(pattern)
    assignments = pattern.bytes.each_with_index.map do |byte, index|
      "\tpattern[#{index}] = #{byte};"
    end.join("\n")
    <<~DAB.chomp
      \tvar pattern = ByteBuffer.new(#{pattern.bytesize});
      #{assignments}
      \tRegex.new(String.new(pattern, #{pattern.bytesize}));
    DAB
  end

  def runtime_error(result)
    result.stderr.lines.map(&:strip).find do |line|
      line.start_with?('vm: Regex', 'vm: String', 'vm: invalid', 'vm: incompatible')
    end
  end

  def normalize_source_lines(source)
    source.gsub("\r\n".b, "\n".b)
  end

  before do
    skip 'native VM has not been built' unless File.executable?(vm)
  end

  it 'transports child Ruby stdout byte-for-byte' do
    Dir.mktmpdir('dab-regex-binary-transport') do |directory|
      emitter = File.join(directory, 'emitter.rb')
      expected = (0..255).to_a.pack('C*')
      File.binwrite(emitter, "STDOUT.write((0..255).to_a.pack('C*'))\n")
      stdout, stderr, status = invoke_binary_ruby(emitter)
      expect([status.exitstatus, stdout, stderr]).to eq([0, expected, ''])
    end
  end

  it 'appends built-in Regex class 20 and exposes only Regex.new' do
    header = File.binread(File.join(root, 'src/cshared/classes.h'))
    defaults = File.binread(File.join(root, 'src/cvm/default_classes.cpp'))
    implementation = normalize_source_lines(File.binread(File.join(root, 'src/cvm/regex.cpp')))
    storage_guard = [
      '    if (arguments[0].data.type != TYPE_LITERALSTRING &&',
      '        arguments[0].data.type != TYPE_DYNAMICSTRING)',
      '    {',
      '        throw DabRuntimeError("Regex.new expects a String pattern");',
      '    }',
    ].join("\n")
    expect(normalize_source_lines(storage_guard.gsub("\n", "\r\n"))).to eq(storage_guard)
    expect(header).to include('CLASS_REGEX         = 20')
    expect(defaults.scan('regex_class.add_static_reg_function').length).to eq(1)
    expect(defaults).to include('regex_class.add_static_reg_function("new"')
    expect(defaults).not_to include('regex_class.add_reg_function')
    expect(defaults.scan('dab_regex_verify_engine();').length).to eq(1)
    expect(implementation).not_to include('dab_regex_verify_engine();')
    expect(implementation).to include(storage_guard)
    expect(implementation.index(storage_guard)).to be < implementation.index('DabLiteralString *')
    expect(implementation.index(storage_guard)).to be < implementation.index('DabDynamicString *')
  end

  it 'accepts source String subclasses through canonical DynamicString storage' do
    source = <<~DAB
      class Evil : String
      {
      }
      func main()
      {
        var pattern = Evil.new("abc");
        print(pattern.class);
        Regex.new(pattern);
        print("|constructed");
      }
    DAB
    result = execute(source)
    expect([result.status, result.stdout, runtime_error(result)]).to eq(
      [0, 'DynamicString|constructed', nil]
    )
  end

  it 'constructs empty, Unicode, property, grapheme, inline-option, and maximum-scalar patterns' do
    patterns = [
      '', 'plain', 'é', "\u{10FFFF}", '\\p{sc=Greek}+', '\\X', '(?i)unicode',
      '(*UTF)(*UCP)unicode',
      'a\\/b', 'a\\\\'
    ]
    patterns.each do |pattern|
      result = execute(main("#{constructor_bytes(pattern)}\n\tprint(\"constructed\");"))
      expect([result.status, result.stdout]).to eq([0, 'constructed'])
      expect(runtime_error(result)).to be_nil
    end
  end

  it 'accepts zero and the exact ByteBuffer boundary with embedded NUL bytes' do
    empty = execute(main("\tvar pattern = ByteBuffer.new(0);\n" \
                         "\tRegex.new(String.new(pattern, 0));\n\tprint(\"empty\");"))
    expect([empty.status, empty.stdout, runtime_error(empty)]).to eq([0, 'empty', nil])

    result = execute(main("#{constructor_bytes("a\0b".b)}\n\tprint(\"constructed\");"))
    expect([result.status, result.stdout]).to eq([0, 'constructed'])
    expect(runtime_error(result)).to be_nil
  end

  it 'rejects negative and oversized String.new ByteBuffer lengths deterministically' do
    cases = ['0 - 1', '2']
    cases.each do |length|
      source = <<~DAB
        \tvar pattern = ByteBuffer.new(1);
        \tpattern[0] = 97;
        \tprint("before");
        \tString.new(pattern, #{length});
        \tprint("after");
      DAB
      result = execute(main(source))
      expect([result.status, result.stdout, runtime_error(result)]).to eq(
        [1, 'before', 'vm: String.new length must be between 0 and the ByteBuffer length.']
      )
      expect(result.stderr).not_to match(/AddressSanitizer|length_error|heap-buffer-overflow/)
    end
  end

  it 'rejects invalid arity and non-String arguments with exact status and diagnostics' do
    cases = {
      "\tRegex.new();" => 'vm: Regex.new expects exactly one argument.',
      "\tRegex.new(\"a\", \"b\");" => 'vm: Regex.new expects exactly one argument.',
      "\tRegex.new(1);" => 'vm: Regex.new expects a String pattern.',
    }
    cases.each do |body, diagnostic|
      result = execute(main(body))
      expect([result.status, result.stdout, runtime_error(result)]).to eq([1, '', diagnostic])
    end
  end

  it 'reports strict UTF-8 failures at zero-based pattern-relative byte offsets' do
    cases = {
      "\x80".b => 0,
      "ab\x80".b => 2,
      "\xE2\x82".b => 0,
      "a\xE2\x82".b => 1,
      "\xED\xA0\x80".b => 0,
      "\xF4\x90\x80\x80".b => 0,
    }
    cases.each do |pattern, offset|
      result = execute(main(constructor_bytes(pattern)))
      expect([result.status, result.stdout]).to eq([1, ''])
      expect(runtime_error(result)).to match(
        /\Avm: invalid UTF-8 Regex pattern at byte #{offset} \(PCRE2 error -\d+\): .+\.\z/
      )
    end
  end

  it 'rejects prohibited or malformed engine grammar with exact byte-oriented errors' do
    ['[', '\\p{NotAProperty}', '\\q', '\\C', '(?u)abc', 'a(*UTF)'].each do |pattern|
      result = execute(main(constructor(pattern)))
      expect([result.status, result.stdout]).to eq([1, ''])
      expect(runtime_error(result)).to match(
        /\Avm: invalid Regex pattern at byte \d+ \(PCRE2 error \d+\): .+\.\z/
      )
    end
  end

  it 'enforces the 65,535-byte input limit before engine allocation' do
    too_long = 'a' * 65_536
    result = execute(main(constructor(too_long)))
    expect([result.status, result.stdout, runtime_error(result)]).to eq(
      [1, '', 'vm: Regex pattern is too long: maximum is 65535 bytes.']
    )

    boundary = execute(main(constructor('a' * 65_535)))
    expect(runtime_error(boundary)).not_to eq('vm: Regex pattern is too long: maximum is 65535 bytes.')
    expect(boundary.status).to eq(1)
    expect(runtime_error(boundary)).to match(/PCRE2 error 120|PCRE2 error 123/)
  end

  it 'preserves the pinned nesting limit' do
    accepted = "#{'(' * 250}a#{')' * 250}"
    rejected = "#{'(' * 251}a#{')' * 251}"
    expect(execute(main(constructor(accepted)))).to have_attributes(status: 0)
    result = execute(main(constructor(rejected)))
    expect([result.status, result.stdout]).to eq([1, ''])
    expect(runtime_error(result)).to match(/PCRE2 error 119/)
  end

  it 'preserves the pinned maximum variable lookbehind' do
    expect(execute(main(constructor('(?<=a{1,255})b')))).to have_attributes(status: 0)
    result = execute(main(constructor('(?<=a{1,256})b')))
    expect([result.status, result.stdout]).to eq([1, ''])
    expect(runtime_error(result)).to match(/PCRE2 error 200/)
  end

  it 'fails closed on an injected engine-profile mismatch before publication' do
    result = execute(main("\tprint(\"before\");"), 'DAB_REGEX_TEST_ENGINE_MISMATCH' => '1')
    expect([result.status, result.stdout, runtime_error(result)]).to eq(
      [
        1,
        '',
        'vm: incompatible Regex engine configuration: expected PCRE2 10.47 with Unicode 16.0.0 strict UTF-8 profile.',
      ]
    )
  end

  it 'maps deterministic allocation failures to one error and never double-frees a compiled handle' do
    %w[source payload proxy].each do |stage|
      result = execute(
        main("\tprint(\"before\");\n#{constructor('abc')}\n\tprint(\"after\");"),
        'DAB_REGEX_TEST_FAIL_ALLOCATION' => stage,
        'DAB_REGEX_TEST_TRACE_LIFETIME' => '1'
      )
      expect([result.status, result.stdout, runtime_error(result)]).to eq(
        [1, 'before', 'vm: Regex construction failed: out of memory.']
      )
      expected_frees = stage == 'source' ? 0 : 1
      expect(result.stderr.scan('regex-test: compiled handle freed').length).to eq(expected_frees)
    end
  end

  it 'shares proxy ownership and frees one successful compiled handle exactly once' do
    source = main("\tvar first = Regex.new(\"abc\");\n\tvar second = first;\n\tprint(\"ok\");")
    result = execute(source, 'DAB_REGEX_TEST_TRACE_LIFETIME' => '1')
    expect([result.status, result.stdout]).to eq([0, 'ok'])
    expect(result.stderr.scan('regex-test: compiled handle freed').length).to eq(1)
  end

  it 'keeps Modern regex construction rejected by EX-009' do
    source_unit = DabSourceUnit.new(input: 'regex.dabm', syntax_profile: DabSyntaxProfile::MODERN)
    parser = DabModernBootstrapParser.new("def main\n/a/\nend\n".b, source_unit: source_unit)
    expect { parser.parse }.to raise_error(
      DabModernBootstrapParseError,
      /runtime Regex construction belongs to EX-010 and executable literal admission belongs to OR-057/
    )
  end
end
