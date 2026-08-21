require 'spec_helper'

require 'digest'
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
  let(:disassembler) { File.join(root, 'bin', "cdisasm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:modern_stdlib) { File.join(root, 'tmp', 'stdlib.dabcb') }

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

  def compile_modern(source)
    skip 'Modern stdlib Ring has not been built' unless File.file?(modern_stdlib)

    Dir.mktmpdir('dab-modern-regex-runtime-spec') do |directory|
      source_path = File.join(directory, 'program.dabm')
      bytecode_path = File.join(directory, 'program.dabcb')
      File.binwrite(source_path, source.b)
      assembly, compiler_error, compiler_status = Open3.capture3(
        RbConfig.ruby,
        File.join(root, 'src/compiler/compiler.rb'),
        source_path,
        "--ring-base[]=#{modern_stdlib}",
        chdir: root,
        binmode: true
      )
      expect(compiler_status.exitstatus).to eq(0), compiler_error
      bytecode, assembler_error, assembler_status = invoke_binary_ruby(
        File.join(root, 'src/tobinary/tobinary.rb'), stdin_data: assembly
      )
      expect(assembler_status.exitstatus).to eq(0), assembler_error
      File.binwrite(bytecode_path, bytecode)
      yield assembly.b, bytecode.b, bytecode_path
    end
  end

  def execute_modern(source, environment = {})
    compile_modern(source) do |_assembly, _bytecode, upper_ring|
      stdout, stderr, status = Open3.capture3(
        environment, vm, modern_stdlib, upper_ring, '--entry=main', chdir: root, binmode: true
      )
      return RegexRuntimeResult.new(stdout: stdout.b, stderr: stderr.b, status: status.exitstatus)
    end
  end

  def execute_transformed_modern(source, environment = {})
    compile_modern(source) do |assembly, _bytecode, _upper_ring|
      transformed = yield assembly
      bytecode, assembler_error, assembler_status = invoke_binary_ruby(
        File.join(root, 'src/tobinary/tobinary.rb'), stdin_data: transformed
      )
      expect(assembler_status.exitstatus).to eq(0), assembler_error
      Dir.mktmpdir('dab-modern-regex-transformed-spec') do |directory|
        upper_ring = File.join(directory, 'program.dabcb')
        File.binwrite(upper_ring, bytecode)
        stdout, stderr, status = Open3.capture3(
          environment, vm, modern_stdlib, upper_ring, '--entry=main', chdir: root, binmode: true
        )
        return RegexRuntimeResult.new(stdout: stdout.b, stderr: stderr.b, status: status.exitstatus)
      end
    end
  end

  def modern_artifact(source)
    skip 'native disassembler has not been built' unless File.executable?(disassembler)

    compile_modern(source) do |assembly, bytecode, bytecode_path|
      disassembly, error, status = Open3.capture3(disassembler, bytecode_path, chdir: root, binmode: true)
      expect(status.exitstatus).to eq(0), error
      return [assembly, bytecode, disassembly.b]
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

  it 'appends built-in Regex class 20 with public new and only one source-unspellable instance target' do
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
    expect(defaults.scan('regex_class.add_reg_function').length).to eq(1)
    expect(defaults).to include('"$modern_regex_case_match"')
    registration = defaults[/for \(const auto &symbol : symbols\).+?auto &fixnum_class/m]
    target_definition = 'const char regex_case_match_target[] = "$modern_regex_case_match";'
    expect(defaults.scan(target_definition).length).to eq(1)
    expect(registration).to include('symbol.value == regex_case_match_target')
    expect(registration).to include('regex_class.add_reg_function(regex_case_match_target')
    guard_index = registration.index('symbol.value == regex_case_match_target')
    method_index = registration.index('regex_class.add_reg_function')
    expect(guard_index).to be < method_index
    regex_section = defaults[/auto &regex_class.+?auto &fixnum_class/m]
    expect(regex_section).not_to include('"matches?"', '"=="')
    expect(defaults.scan('dab_regex_verify_engine();').length).to eq(1)
    expect(implementation).not_to include('dab_regex_verify_engine();')
    expect(implementation).to include(storage_guard)
    expect(implementation.index(storage_guard)).to be < implementation.index('DabLiteralString *')
    expect(implementation.index(storage_guard)).to be < implementation.index('DabDynamicString *')
    expect(implementation.index('arguments.size() != 1', implementation.index('dab_regex_match')))
      .to be < implementation.index('dynamic_cast<DabRegex *>', implementation.index('dab_regex_match'))
    expect(implementation).to include(
      'subject_value.data.type != TYPE_LITERALSTRING',
      'subject_value.data.type != TYPE_DYNAMICSTRING',
      'storage->klass != CLASS_LITERALSTRING',
      'storage->klass != CLASS_DYNAMICSTRING'
    )
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

  it 'constructs reached Modern literals while leaving dead and unselected patterns uncompiled' do
    source = <<~DAB.b
      def main
        /[/ if false
        if false
          /#{"\xFF".b}/
        end
        //
        /a\\/b/
        print("constructed")
      end
    DAB
    result = execute_modern(source)

    expect([result.status, result.stdout, runtime_error(result)]).to eq([0, 'constructed', nil])
  end

  it 'preserves raw Modern NUL, quote, hash, slash escape, and invalid UTF bytes' do
    valid_body = "a\0\"#\\/b".b
    valid = execute_modern("def main\n/#{valid_body}/\nprint(\"valid\")\nend\n".b)
    expect([valid.status, valid.stdout, runtime_error(valid)]).to eq([0, 'valid', nil])

    invalid = execute_modern("def main\nprint(\"before\")\n/a\xFF/\nprint(\"after\")\nend\n".b)
    expect([invalid.status, invalid.stdout]).to eq([1, 'before'])
    expect(runtime_error(invalid)).to match(
      /\Avm: invalid UTF-8 Regex pattern at byte 1 \(PCRE2 error -\d+\): .+\.\z/
    )
  end

  it 'keeps Modern engine and length failures at runtime with prior output visible' do
    malformed = execute_modern("def main\nprint(\"before\")\n/[/\nprint(\"after\")\nend\n")
    expect([malformed.status, malformed.stdout]).to eq([1, 'before'])
    expect(runtime_error(malformed)).to match(
      /\Avm: invalid Regex pattern at byte \d+ \(PCRE2 error \d+\): .+\.\z/
    )

    too_long = execute_modern("def main\n/#{'a' * 65_536}/\nend\n")
    expect([too_long.status, too_long.stdout, runtime_error(too_long)]).to eq(
      [1, '', 'vm: Regex pattern is too long: maximum is 65535 bytes.']
    )
    boundary = execute_modern("def main\n/#{'a' * 65_535}/\nend\n")
    expect(runtime_error(boundary)).not_to eq('vm: Regex pattern is too long: maximum is 65535 bytes.')
  end

  it 'emits only existing Regex construction instructions deterministically' do
    source = <<~DAB
      def main
        /a\\/b/
        print("or057-proof")
      end
    DAB
    first = modern_artifact(source)
    second = modern_artifact(source)

    expect(second).to eq(first)
    assembly = first.fetch(0)
    expect(assembly).to include('LOAD_STRING', 'LOAD_CLASS')
    expect(assembly).to match(/LOAD_CLASS R\d+, 20/)
    expect(assembly).to match(/INSTCALL (?:R\d+|RNIL), R\d+, S\d+/)
    expect(assembly).not_to match(/^\s+(?:REGEX|PCRE)[A-Z_]*\b/i)
    expect(first.map { |bytes| Digest::SHA256.hexdigest(bytes) }).to all(match(/\A[0-9a-f]{64}\z/))

    run_a = execute_modern(source)
    run_b = execute_modern(source)
    expect([run_a.status, run_a.stdout]).to eq([0, 'or057-proof'])
    expect(runtime_error(run_a)).to be_nil
    expect(run_b).to eq(run_a)
  end

  it 'matches reached Modern Regex case patterns with ordinary search, explicit anchors, and Unicode' do
    source = <<~'DAB'
      def subject():String
      print("subject|")
      return "prefix-abcdefghijklmnop-suffix"
      end
      def main
      case subject()
      when /^abcdefghijklmnop/
      print("wrong-anchor|")
      when /\p{sc=Greek}+/
      print("unicode|")
      when /[/
      print("wrong-later|")
      else
      print("wrong-else|")
      end
      case "anything"
      when //
      print("empty|")
      end
      case "abc"
      when /^b/
      print("wrong-second-anchor|")
      else
      print("anchored")
      end
      end
    DAB
    result = execute_transformed_modern(source, 'DAB_REGEX_TEST_TRACE_LIFETIME' => '1') do |assembly|
      unicode_subject = 'prefix-Καλημέρα-suffix'.b
      replacement = (unicode_subject.bytes + [0]).map do |byte|
        "                                 W_BYTE #{byte}"
      end.join("\n")
      placeholder = 'prefix-abcdefghijklmnop-suffix'
      expect(assembly.scan(%(W_STRING "#{placeholder}")).length).to eq(1)
      transformed = assembly.sub(/\s+W_STRING "#{placeholder}" /, "\n#{replacement}")
      expect(transformed).to be_ascii_only
      transformed
    end

    expect([result.status, result.stdout, runtime_error(result)])
      .to eq([0, 'subject|unicode|empty|anchored', nil])
    expect(result.stderr.scan('regex-test: compiled handle freed').length).to eq(4)
  end

  it 'preserves embedded NUL in the exact-length subject storage used by matching' do
    source = <<~'DAB'
      def main
      case "ab"
      when /\x00/
      print("nul")
      else
      print("wrong")
      end
      end
    DAB
    result = execute_transformed_modern(source) do |assembly|
      replacement = [
        '                                 W_BYTE 97',
        '                                 W_BYTE 0',
        '                                 W_BYTE 0',
      ].join("\n")
      expect(assembly.scan('W_STRING "ab"').length).to eq(1)
      assembly.sub(/\s+W_STRING "ab" /, "\n#{replacement}")
    end

    expect([result.status, result.stdout, runtime_error(result)]).to eq([0, 'nul', nil])
  end

  it 'reports invalid UTF-8 subjects at exact zero-based byte offsets and stops later code' do
    source = <<~DAB
      def main
      print("before|")
      case "abc"
      when /./
      print("wrong-match|")
      end
      print("after")
      end
    DAB
    result = execute_transformed_modern(source) do |assembly|
      replacement = [
        '                                 W_BYTE 97',
        '                                 W_BYTE 128',
        '                                 W_BYTE 99',
        '                                 W_BYTE 0',
      ].join("\n")
      expect(assembly.scan('W_STRING "abc"').length).to eq(1)
      assembly.sub(/\s+W_STRING "abc" /, "\n#{replacement}")
    end

    expect([result.status, result.stdout]).to eq([1, 'before|'])
    expect(runtime_error(result)).to match(
      /\Avm: invalid UTF-8 Regex match subject at byte 1 \(PCRE2 error -\d+\): .+\.\z/
    )
  end

  it 'maps all bounded matching failures exactly without publishing a Boolean or running later code' do
    cases = {
      'match_limit' => 'vm: Regex match limit exceeded.',
      'depth_limit' => 'vm: Regex match depth limit exceeded.',
      'heap_limit' => 'vm: Regex match heap limit exceeded.',
      'out_of_memory' => 'vm: Regex match failed: out of memory.',
    }
    source = <<~DAB
      def main
      print("before")
      case "subject"
      when /subject/
      print("after")
      end
      end
    DAB
    cases.each do |injected, diagnostic|
      result = execute_modern(source, 'DAB_REGEX_TEST_MATCH_ERROR' => injected)
      expect([result.status, result.stdout, runtime_error(result)]).to eq([1, 'before', diagnostic])
    end
  end

  it 'lets pattern-side limits lower but not raise the configured match ceilings' do
    failing_subject = "#{'a' * 20_000}X"
    cases = {
      '(*LIMIT_MATCH=10)(?:a+)+$' => 'vm: Regex match limit exceeded.',
      '(*LIMIT_MATCH=200000)(?:a+)+$' => 'vm: Regex match limit exceeded.',
      '(*LIMIT_DEPTH=1)(?:a+)+$' => 'vm: Regex match depth limit exceeded.',
      '(*LIMIT_HEAP=1)(?:a|b)+$' => 'vm: Regex match heap limit exceeded.',
    }
    cases.each do |pattern, diagnostic|
      subject = pattern.include?('LIMIT_HEAP') ? 'a' * 20_000 : failing_subject
      source = <<~DAB
        def main
        print("before")
        case "#{subject}"
        when /#{pattern}/
        print("after")
        end
        end
      DAB
      result = execute_modern(source)
      expect([result.status, result.stdout, runtime_error(result)]).to eq([1, 'before', diagnostic])
    end
  end

  it 'pins one bounded match context, minimal match data, strict checking, and exact limits' do
    implementation = normalize_source_lines(File.binread(File.join(root, 'src/cvm/regex.cpp')))

    expect(implementation).to include(
      'pcre2_set_match_limit(context.get(), 100000)',
      'pcre2_set_depth_limit(context.get(), 1000)',
      'pcre2_set_heap_limit(context.get(), 8192)',
      'pcre2_match_data_create(1, nullptr)',
      'pcre2_match(code, subject, subject_size, 0, 0, match_data.get(), context.get())'
    )
    expect(implementation).not_to include('PCRE2_NO_UTF_CHECK')
  end
end
