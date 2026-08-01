require 'spec_helper'

require 'rbconfig'
require 'stringio'

require_relative '../lib/dab/unsafe_ffi_capability_smoke'

module UnsafeFfiCapabilitySmokeSpecSupport
  class FakeExecutor
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def call(command, input:, chdir:, timeout:, environment: {})
      calls << {
        command: command,
        input: input,
        chdir: chdir,
        timeout: timeout,
        environment: environment,
      }
      @results.shift || raise('unexpected command')
    end
  end

  class FakeCommands
    def compiler(source)
      ['compiler', source]
    end

    def assembler
      ['assembler']
    end

    def vm(bytecode, allow_unsafe_ffi:)
      ['cvm', ('--allow-unsafe-ffi' if allow_unsafe_ffi), bytecode].compact
    end
  end
end

describe Dab::UnsafeFfiCapabilitySmoke::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  def result(stdout: '', stderr: '', exit_code: 0, timed_out: false)
    Dab::UnsafeFfiCapabilitySmoke::CommandResult.new(
      stdout: stdout.b,
      stderr: stderr.b,
      exit_code: exit_code,
      timed_out: timed_out
    )
  end

  def denied_result
    result(
      stderr: "VM options: autorun yes raw no cov no\n" \
              "vm: unsafe FFI is disabled; use --allow-unsafe-ffi only for trusted local code.\n",
      exit_code: 1
    )
  end

  def allowed_unix_result
    result(
      stdout: '19',
      stderr: "VM options: autorun yes raw no cov no\n" \
              "vm: readjust 'unsafe_ffi_abs' to libc function 'abs'\n"
    )
  end

  def allowed_windows_result
    result(
      stderr: "VM options: autorun yes raw no cov no\n" \
              "vm: newformat: section 0: name 'data' address 00000000000000e8/232 length 10\n" \
              "vm: function import not supported on windows yet.\n",
      exit_code: 1
    )
  end

  def run_with(results, windows: false, environment: {})
    executor = UnsafeFfiCapabilitySmokeSpecSupport::FakeExecutor.new(results)
    runner = described_class.new(
      root: root,
      executor: executor,
      commands: UnsafeFfiCapabilitySmokeSpecSupport::FakeCommands.new,
      environment: environment,
      output: output,
      error: error,
      windows: windows
    )
    [runner.run, executor]
  end

  it 'checks the raw syscall path denied first and then with the explicit opt-in' do
    status, executor = run_with([
                                  result(stdout: 'assembly'),
                                  result(stdout: 'bytecode'),
                                  denied_result,
                                  allowed_unix_result,
                                ])

    expect(status).to eq(0)
    expect(executor.calls.map { |call| call.fetch(:command).first }).to eq(
      %w[compiler assembler cvm cvm]
    )
    expect(executor.calls[2].fetch(:command)).not_to include('--allow-unsafe-ffi')
    expect(executor.calls[3].fetch(:command)).to include('--allow-unsafe-ffi')
    expect(output.string).to include('default denied, explicit opt-in checked')
    expect(error.string).to eq('')
  end

  it 'preserves the unsupported Windows boundary after explicit opt-in' do
    status, = run_with(
      [result(stdout: 'assembly'), result(stdout: 'bytecode'), denied_result, allowed_windows_result],
      windows: true
    )

    expect(status).to eq(0)
    expect(error.string).to eq('')
  end

  it 'fails when default execution succeeds and therefore does not test the opted-in path' do
    status, executor = run_with([
                                  result(stdout: 'assembly'),
                                  result(stdout: 'bytecode'),
                                  allowed_unix_result,
                                ])

    expect(status).to eq(1)
    expect(executor.calls.length).to eq(3)
    expect(error.string).to include('FAILED during denied-by-default runtime contract')
  end

  it 'fails on any denied diagnostic or status drift' do
    status, = run_with([
                         result(stdout: 'assembly'),
                         result(stdout: 'bytecode'),
                         result(stderr: 'different denial', exit_code: 2),
                       ])

    expect(status).to eq(1)
    expect(error.string).to include('expected exit 1')
    expect(error.string).to include('different denial')
  end

  it 'fails when the VM emits an unexpected additional diagnostic' do
    denied_with_extra_stderr = denied_result
    denied_with_extra_stderr.stderr << "vm: unexpected warning\n"
    status, executor = run_with([
                                  result(stdout: 'assembly'),
                                  result(stdout: 'bytecode'),
                                  denied_with_extra_stderr,
                                ])

    expect(status).to eq(1)
    expect(executor.calls.length).to eq(3)
    expect(error.string).to include('FAILED during denied-by-default runtime contract')
    expect(error.string).to include('vm: unexpected warning')
  end

  it 'passes the selected sanitizer environment to every external stage' do
    environment = {'ASAN_OPTIONS' => 'strict-contract'}
    status, executor = run_with(
      [result(stdout: 'assembly'), result(stdout: 'bytecode'), denied_result, allowed_unix_result],
      environment: environment
    )

    expect(status).to eq(0)
    expect(executor.calls.map { |call| call.fetch(:environment) }).to all(eq(environment))
  end

  it 'attributes compiler failures and preserves their nonzero status' do
    status, executor = run_with([result(stderr: 'bad source', exit_code: 7)])

    expect(status).to eq(7)
    expect(executor.calls.length).to eq(1)
    expect(error.string).to include('FAILED during compiler')
    expect(error.string).to include('exit status: 7')
    expect(error.string).to include('captured stderr: "bad source"')
  end
end

describe Dab::UnsafeFfiCapabilitySmoke::Commands do
  let(:root) { File.expand_path('..', __dir__) }

  it 'keeps assembler stdout binary on Windows-compatible Ruby runtimes' do
    command = described_class.new(root: root).assembler

    expect(command).to eq(
      [
        RbConfig.ruby,
        '-e',
        'STDOUT.binmode; load ARGV.shift',
        File.join(root, 'src/tobinary/tobinary.rb'),
      ]
    )
  end

  it 'adds exactly one explicit unsafe FFI flag only to the opted-in VM command' do
    commands = described_class.new(root: root)
    bytecode = File.join(root, 'path with spaces', 'program.dabcb')

    expect(commands.vm(bytecode, allow_unsafe_ffi: false)).to eq(
      [File.join(root, 'bin', "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}"), bytecode]
    )
    expect(commands.vm(bytecode, allow_unsafe_ffi: true)).to eq(
      [
        File.join(root, 'bin', "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}"),
        '--allow-unsafe-ffi',
        bytecode,
      ]
    )
  end

  it 'can select each isolated sanitizer VM without changing source semantics' do
    bytecode = File.join(root, 'program.dabcb')
    command = described_class.new(
      root: root,
      binary_directory: 'bin/address-sanitizer'
    ).vm(bytecode, allow_unsafe_ffi: true)

    expect(command.first).to eq(
      File.join(root, 'bin/address-sanitizer', "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}")
    )
    expect(command.drop(1)).to eq(['--allow-unsafe-ffi', bytecode])
  end
end
