require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'set'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'minimal Modern main bootstrap' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:source_path) { File.join(root, 'test/modern_minimal_main/program.dabm') }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:clipboard_fallback) do
    "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
  end
  let(:near_misses) do
    {
      'empty name' => ["def \nend\n".b, {offset: 4, line: 2, column: 0}],
      'another name' => ["def worker\nend\n".b, {offset: 4, line: 1, column: 4}],
      'parentheses and parameters' => ["def main()\nend\n".b, {offset: 8, line: 1, column: 8}],
      'return annotation' => ["def main: Object\nend\n".b, {offset: 8, line: 1, column: 8}],
      'body content' => ["def main\nvalue\nend\n".b, {offset: 9, line: 2, column: 0}],
      'duplicate declaration' => ["def main\nend\ndef main\nend\n".b, {offset: 13, line: 3, column: 0}],
      'leading token' => [" def main\nend\n".b, {offset: 0, line: 1, column: 0}],
      'trailing token' => ["def main\nend\nextra\n".b, {offset: 13, line: 3, column: 0}],
      'comment' => ["# comment\ndef main\nend\n".b, {offset: 0, line: 1, column: 0}],
      'semicolon' => ["def main;\nend\n".b, {offset: 8, line: 1, column: 8}],
      'missing end' => ["def main\n".b, {offset: 9, line: 2, column: 0}],
      'incomplete def' => ['de'.b, {offset: 0, line: 1, column: 0}],
      'incomplete end' => ["def main\nen\n".b, {offset: 9, line: 2, column: 0}],
      'CR-only' => ["def main\rend\r".b, {offset: 8, line: 1, column: 8}],
      'CRLF' => ["def main\r\nend\r\n".b, {offset: 8, line: 1, column: 8}],
      'missing final LF' => ["def main\nend".b, {offset: 12, line: 2, column: 3}],
      'NUL body' => ["def main\n\0\nend\n".b, {offset: 9, line: 2, column: 0}],
    }
  end

  def invoke(*command, input: nil)
    Open3.capture3(*command, stdin_data: input, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(clipboard_fallback)
  end

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq [0, "PASS #{artifact}\n"]
    expect(tool_stderr(stderr)).not_to include('exception:', 'FAILED')
    artifact
  end

  def compile_application(directory, lower:, basename: 'application')
    assembly, stderr, status = invoke(
      RbConfig.ruby,
      compiler,
      source_path,
      "--ring-base[]=#{lower}"
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq [0, '']

    bytecode, assembler_stderr, assembler_status = invoke(
      RbConfig.ruby,
      assembler,
      input: assembly
    )
    expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq [0, '']
    artifact = File.join(directory, "#{basename}.dabcb")
    File.binwrite(artifact, bytecode)
    {assembly: assembly, artifact: artifact, bytecode: bytecode}
  end

  def parse_pipeline(lower, upper)
    reader = DabBinReader.new
    lower_data = reader.parse_dab_binary(File.binread(lower), [])
    upper_data = reader.parse_dab_binary(File.binread(upper), lower_data.fetch(:all_symbols))
    [lower_data, upper_data]
  end

  def run_vm(directory, inputs, basename:)
    application_stdout = File.join(directory, "#{basename}.application-stdout")
    process_stdout, host_stderr, status = invoke(vm, "--out=#{application_stdout}", *inputs)
    {
      status: status.exitstatus,
      process_stdout: process_stdout,
      application_stdout: File.binread(application_stdout),
      host_stderr: host_stderr,
    }
  end

  def artifact_diagnostic_patterns(data, seen_classes)
    header = data.fetch(:header)
    address = '(?:0x)?[0-9a-fA-F]+'
    patterns = [
      /^vm: newformat: h: #{header.fetch(:size_of_header)}, d: #{header.fetch(:size_of_data)}, s: #{header.fetch(:sections_count)}$/,
      /^vm: offset is #{header.fetch(:offset)}$/,
    ]
    header.fetch(:sections).each_with_index do |section, index|
      absolute_address = header.fetch(:offset) + section.fetch(:address)
      patterns << /^vm: newformat: section #{index}: name '#{Regexp.escape(section.fetch(:name))}' address #{address}\/#{absolute_address} length #{section.fetch(:length)}$/
    end

    symbol_section = header.fetch(:sections).find { |section| section.fetch(:name) == 'symb' }
    patterns << /^readbin: #{symbol_section.fetch(:length) / 8} symbol\(s\) to read$/ if symbol_section

    class_section = header.fetch(:sections).find { |section| section.fetch(:name) == 'clas' }
    if class_section
      patterns << /^classad=#{address}$/
      data.fetch(:klasses).each do |klass|
        patterns << /^\[class\] index=#{klass.fetch(:index)} parent=#{klass.fetch(:parent_index)} symbol=\d+ template=0$/
        next if seen_classes.include?(klass.fetch(:index))

        parent = STANDARD_CLASSES_MAP.fetch(klass.fetch(:parent_index))
        patterns << /^vm: add class <#{Regexp.escape(klass.fetch(:symbol))}> \(parent = <#{Regexp.escape(parent)}>\)\.$/
        seen_classes << klass.fetch(:index)
      end
    end

    data.fetch(:functions).each do |function|
      patterns << /^vm: add function <#{Regexp.escape(function.fetch(:symbol))}>\.$/
    end
    code_section = header.fetch(:sections).find { |section| section.fetch(:name) == 'code' }
    code_address = header.fetch(:offset) + code_section.fetch(:address)
    patterns << /^vm: seek initial code pointer to #{code_address}$/
    patterns
  end

  def expect_success_host_diagnostics(stderr, lower_data, upper_data)
    seen_classes = STANDARD_CLASSES_MAP.keys.to_set
    patterns = [
      /^vm: predefine default classes$/,
      /^VM options: autorun yes raw no cov no$/,
      *artifact_diagnostic_patterns(lower_data, seen_classes),
      *artifact_diagnostic_patterns(upper_data, seen_classes),
      /^vm: define defaults$/,
      /^vm: define default classes$/,
      /^vm: define default functions$/,
      /^vm: trying to initialize attributes$/,
      /^vm: initialize attributes \(__init_0\)$/,
      /^vm: initialize attributes \(__init_\d+\)$/,
      /^vm: VM destroyed!$/,
      /^vm: reset \$VM pointer$/,
    ]
    lines = stderr.lines(chomp: true)

    expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
    expect(lines.length).to eq(patterns.length)
    lines.zip(patterns).each_with_index do |(line, pattern), index|
      expect(line).to match(pattern), "unexpected VM host diagnostic line #{index + 1}: #{line.inspect}"
    end
  end

  it 'parses exactly one empty no-argument main declaration into the existing typed AST boundary' do
    source_unit = DabSourceUnit.new(
      input: source_path,
      syntax_profile: DabSyntaxProfile::MODERN
    )
    declaration = DabModernBootstrapParser.new(File.binread(source_path), source_unit: source_unit).parse
    unit = DabNodeUnit.new

    function = declaration.lower_into(unit)

    expect(declaration.source_unit).to equal(source_unit)
    expect(function).to be_a(DabNodeFunction)
    expect(function.identifier).to eq 'main'
    expect(function.arglist).to be_empty
    expect(function.blocks[0]).to be_empty
    expect(unit.has_function?('main')).to equal(function)
  end

  it 'rejects every excluded bootstrap shape at the first shared-scanner location' do
    source_unit = DabSourceUnit.new(
      input: 'near-miss.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    near_misses.each do |description, (source, location)|
      expect do
        DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq 'unsupported Dab syntax profile "modern": parser is not implemented'
        expect(error.source_location.to_h).to eq(location), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'reports exact compiler diagnostics for every near miss over the Legacy stdlib Ring' do
    Dir.mktmpdir('dab-modern-minimal-main-diagnostics') do |directory|
      lower = build_stdlib(directory)

      near_misses.each_with_index do |(description, (source, location)), index|
        path = File.join(directory, sprintf('near-miss-%02d.dabm', index))
        File.binwrite(path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          path,
          "--ring-base[]=#{lower}"
        )
        expected =
          "compiler: #{path}:#{location.fetch(:line)}:#{location.fetch(:column)}: error: " \
          "unsupported Dab syntax profile \"modern\": parser is not implemented\n"

        aggregate_failures(description) do
          expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq [2, '', expected]
        end
      end
    end
  end

  it 'keeps the canonical declaration unsupported without a lower Ring' do
    stdout, stderr, status = invoke(RbConfig.ruby, compiler, source_path)

    expected = [
      2,
      '',
      "compiler: #{source_path}:1:0: error: " \
      "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
    ]
    expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq expected
  end

  it 'builds and runs two byte-identical Modern upper Rings over separate Legacy stdlib Rings' do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-minimal-main') do |temporary_root|
      results = Array.new(2) do |index|
        directory = File.join(temporary_root, "run-#{index}")
        Dir.mkdir(directory)
        lower = build_stdlib(directory)
        upper = compile_application(directory, lower: lower)
        lower_data, upper_data = parse_pipeline(lower, upper.fetch(:artifact))
        runtime = run_vm(directory, [lower, upper.fetch(:artifact)], basename: 'success')

        expect(runtime.slice(:status, :process_stdout, :application_stdout)).to eq(
          status: 0,
          process_stdout: '',
          application_stdout: ''
        )
        expect_success_host_diagnostics(runtime.fetch(:host_stderr), lower_data, upper_data)
        expect(upper.fetch(:assembly)).to include(
          'Fmain:',
          'RETURN RNIL',
          'W_METHOD',
          '/* main'
        )
        expect(upper.fetch(:assembly)).not_to include('KERNEL_CALL', 'WARN')

        main = upper_data.fetch(:functions).find { |function| function.fetch(:symbol) == 'main' }
        expect(main).to include(klass: nil, args: [], ret: {klass: 'Object'})
        upper_symbols = ["__init_#{File.size(lower)}", 'main']
        expect(upper_data.fetch(:symbols)).to eq upper_symbols
        expect(upper_data.fetch(:functions).map { |function| function.fetch(:symbol) }).to eq upper_symbols
        expect(upper_data.fetch(:header).fetch(:offset)).to eq File.size(lower)
        expect(main.fetch(:address)).to be > File.size(lower)
        expect(upper_data.fetch(:header).fetch(:sections).map { |section| section.fetch(:name) }).not_to include('data')
        expect(upper.fetch(:bytecode).bytesize).to be < File.size(lower)
        expect(lower_data.fetch(:functions).map { |function| function.fetch(:symbol) }).to include('puts')
        expect(lower_data.fetch(:klasses).map { |klass| klass.fetch(:symbol) }).to include('Set')

        {
          directory: directory,
          lower: lower,
          upper: upper,
          lower_data: lower_data,
          upper_data: upper_data,
          runtime: runtime,
        }
      end

      first, second = results
      expect(File.binread(first.fetch(:lower))).to eq File.binread(second.fetch(:lower))
      expect(first.fetch(:upper).fetch(:bytecode)).to eq second.fetch(:upper).fetch(:bytecode)
      expect(first.fetch(:runtime).fetch(:host_stderr)).to eq second.fetch(:runtime).fetch(:host_stderr)

      removed = run_vm(
        first.fetch(:directory),
        [first.fetch(:upper).fetch(:artifact)],
        basename: 'removed-lower'
      )
      expect(removed.slice(:status, :process_stdout, :application_stdout)).to eq(
        status: 1,
        process_stdout: '',
        application_stdout: ''
      )
      expected_removed_diagnostics = [
        'vm: predefine default classes',
        'VM options: autorun yes raw no cov no',
        'vm: invalid bytecode String/symbol data: symb entry 0 reference is outside the artifact.',
        'vm: VM destroyed!',
        'vm: reset $VM pointer',
      ]
      expect(removed.fetch(:host_stderr).lines(chomp: true)).to eq expected_removed_diagnostics

      reversed = run_vm(
        first.fetch(:directory),
        [first.fetch(:upper).fetch(:artifact), first.fetch(:lower)],
        basename: 'reversed-rings'
      )
      # The POSIX handler maps this existing loader crash to exit 1. Windows
      # reports the native abnormal termination without a normal exit status.
      expect(reversed.slice(:status, :process_stdout, :application_stdout)).to eq(
        status: Gem.win_platform? ? nil : 1,
        process_stdout: '',
        application_stdout: ''
      )
      expect(reversed.fetch(:host_stderr)).to include('Error: signal') unless Gem.win_platform?
      expect(reversed.fetch(:host_stderr)).not_to match(/sanitizer|warning|KERNEL_WARN/i)
      expect(reversed.fetch(:host_stderr)).not_to include('vm: initialize attributes', 'vm: add function <main>.')

      corrupt_lower = File.join(first.fetch(:directory), 'corrupt-stdlib.dabcb')
      corrupt_bytes = File.binread(first.fetch(:lower))
      corrupt_bytes[0, 3] = 'BAD'
      File.binwrite(corrupt_lower, corrupt_bytes)
      corrupt = run_vm(
        first.fetch(:directory),
        [corrupt_lower, first.fetch(:upper).fetch(:artifact)],
        basename: 'corrupt-lower'
      )
      expect(corrupt.slice(:status, :process_stdout, :application_stdout)).to eq(
        status: 1,
        process_stdout: '',
        application_stdout: ''
      )
      expected_corrupt_diagnostics = [
        'vm: predefine default classes',
        'VM options: autorun yes raw no cov no',
        'vm: invalid bytecode header: magic must be DAB.',
        'vm: VM destroyed!',
        'vm: reset $VM pointer',
      ]
      expect(corrupt.fetch(:host_stderr).lines(chomp: true)).to eq expected_corrupt_diagnostics
    end
  end
end
