require 'spec_helper'

require 'rbconfig'
require 'stringio'
require 'tmpdir'

require_relative '../lib/dab/legacy_source_vm_smoke'

module LegacySourceVmSmokeSpecSupport
  class FakeExecutor
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def call(command, input:, chdir:, timeout:)
      calls << {command: command, input: input, chdir: chdir, timeout: timeout}
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

    def vm(bytecode)
      ['cvm', bytecode]
    end
  end
end

describe Dab::LegacySourceVmSmoke::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  def result(stdout: '', stderr: '', exit_code: 0, timed_out: false)
    Dab::LegacySourceVmSmoke::CommandResult.new(
      stdout: stdout.b,
      stderr: stderr.b,
      exit_code: exit_code,
      timed_out: timed_out
    )
  end

  def successful_results(first_bytecode: 'portable bytecode', second_bytecode: 'portable bytecode',
                         first_stdout: 'legacy source-to-VM smoke: 42',
                         second_stdout: 'legacy source-to-VM smoke: 42',
                         first_stderr: 'vm diagnostics', second_stderr: 'vm diagnostics')
    [
      result(stdout: 'assembly one', stderr: 'compiler diagnostics'),
      result(stdout: first_bytecode, stderr: 'assembler diagnostics'),
      result(stdout: first_stdout, stderr: first_stderr),
      result(stdout: 'assembly two', stderr: 'compiler diagnostics'),
      result(stdout: second_bytecode, stderr: 'assembler diagnostics'),
      result(stdout: second_stdout, stderr: second_stderr),
    ]
  end

  def run_with(results, temporary_directory_factory: nil)
    executor = LegacySourceVmSmokeSpecSupport::FakeExecutor.new(results)
    runner = described_class.new(
      root: root,
      executor: executor,
      commands: LegacySourceVmSmokeSpecSupport::FakeCommands.new,
      temporary_directory_factory: temporary_directory_factory,
      output: output,
      error: error
    )
    [runner.run, executor]
  end

  it 'runs compiler, assembler, and native VM twice and accepts byte-identical portable bytecode' do
    status, executor = run_with(successful_results)

    expect(status).to eq(0)
    expect(executor.calls.map { |call| call[:command].first }).to eq(
      %w[compiler assembler cvm compiler assembler cvm]
    )
    expect(executor.calls.map { |call| call[:timeout] }).to eq([30, 30, 10, 30, 30, 10])
    expect(output.string).to match(/PASSED \(2 runs, 17 byte portable bytecode, sha256 [0-9a-f]{64}\)/)
    expect(error.string).to eq('')
  end

  it 'uses independent owned temporary paths with spaces and removes them after success' do
    directories = []
    factory = lambda do |&block|
      Dir.mktmpdir('dab-legacy-smoke-spec') do |owned_root|
        workspace = File.join(owned_root, 'workspace with spaces')
        Dir.mkdir(workspace)
        directories << workspace
        block.call(workspace)
      end
    end

    status, executor = run_with(successful_results, temporary_directory_factory: factory)

    expect(status).to eq(0)
    expect(directories.length).to eq(2)
    expect(directories.uniq).to eq(directories)
    expect(directories).to all(include(' '))
    expect(directories).to all(satisfy { |directory| !Dir.exist?(directory) })
    compiler_sources = executor.calls.values_at(0, 3).map { |call| call[:command].last }
    vm_bytecode = executor.calls.values_at(2, 5).map { |call| call[:command].last }
    expect(compiler_sources + vm_bytecode).to all(include(' '))
  end

  it 'attributes compiler failure, preserves its status, and does not continue' do
    directories = []
    factory = lambda do |&block|
      Dir.mktmpdir('dab-legacy-smoke-failure-spec') do |owned_root|
        workspace = File.join(owned_root, 'workspace with spaces')
        Dir.mkdir(workspace)
        directories << workspace
        block.call(workspace)
      end
    end
    status, executor = run_with(
      [result(stderr: 'bad source', exit_code: 7)],
      temporary_directory_factory: factory
    )

    expect(status).to eq(7)
    expect(executor.calls.length).to eq(1)
    expect(directories).to all(satisfy { |directory| !Dir.exist?(directory) })
    expect(error.string).to include('FAILED during compiler')
    expect(error.string).to include('command: compiler')
    expect(error.string).to include('exit status: 7')
    expect(error.string).to include('captured stderr: "bad source"')
  end

  it 'attributes assembler failure and does not execute the VM' do
    status, executor = run_with([
                                  result(stdout: 'assembly'),
                                  result(stdout: 'partial bytecode', stderr: 'bad assembly', exit_code: 8),
                                ])

    expect(status).to eq(8)
    expect(executor.calls.map { |call| call[:command].first }).to eq(%w[compiler assembler])
    expect(error.string).to include('FAILED during assembler')
    expect(error.string).to include('captured stdout: "partial bytecode"')
    expect(error.string).to include('captured stderr: "bad assembly"')
  end

  it 'attributes native VM failure and does not start the second build' do
    status, executor = run_with([
                                  result(stdout: 'assembly'),
                                  result(stdout: 'bytecode'),
                                  result(stdout: 'partial output', stderr: 'bad bytecode', exit_code: 9),
                                ])

    expect(status).to eq(9)
    expect(executor.calls.map { |call| call[:command].first }).to eq(%w[compiler assembler cvm])
    expect(error.string).to include('FAILED during native VM')
    expect(error.string).to include('captured stdout: "partial output"')
    expect(error.string).to include('captured stderr: "bad bytecode"')
  end

  it 'reports timeouts with stage, limit, status, and captured diagnostics' do
    status, executor = run_with([
                                  result(stderr: 'still compiling', exit_code: 124, timed_out: true),
                                ])

    expect(status).to eq(124)
    expect(executor.calls.length).to eq(1)
    expect(error.string).to include('FAILED during compiler (timed out after 30 seconds)')
    expect(error.string).to include('exit status: 124')
    expect(error.string).to include('captured stderr: "still compiling"')
  end

  it 'fails closed when independent builds produce different bytecode' do
    status, = run_with(successful_results(first_bytecode: 'first', second_bytecode: 'second'))

    expect(status).to eq(1)
    expect(error.string).to include('FAILED during bytecode reproducibility contract')
    expect(error.string).to include('run 1 sha256')
    expect(error.string).to include('run 2 sha256')
  end

  it 'reports exact runtime stdout mismatches after both reproducible executions' do
    status, executor = run_with(successful_results(first_stdout: 'wrong'))

    expect(status).to eq(1)
    expect(executor.calls.length).to eq(6)
    expect(error.string).to include('FAILED during runtime stdout contract')
    expect(error.string).to include('expected "legacy source-to-VM smoke: 42"')
    expect(error.string).to include('run 1 "wrong"')
  end

  it 'requires runtime stderr to match byte-for-byte across the two executions' do
    status, = run_with(successful_results(second_stderr: 'different diagnostics'))

    expect(status).to eq(1)
    expect(error.string).to include('FAILED during runtime stderr contract')
    expect(error.string).to include('run 1 "vm diagnostics"')
    expect(error.string).to include('run 2 "different diagnostics"')
  end
end

describe Dab::LegacySourceVmSmoke::Commands do
  it 'uses the platform-native VM executable suffix' do
    root = File.expand_path('..', __dir__)
    bytecode = File.join(root, 'path with spaces', 'program.dabcb')

    command = described_class.new(root: root).vm(bytecode)

    expect(command).to eq(
      [File.join(root, 'bin', "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}"), bytecode]
    )
  end
end

describe Dab::LegacySourceVmSmoke::SystemExecutor do
  let(:root) { File.expand_path('..', __dir__) }

  it 'preserves arguments with spaces and captures both output streams' do
    result = described_class.new.call(
      [RbConfig.ruby, '-e', 'STDOUT.write(ARGV.fetch(0)); STDERR.write("diagnostic")', 'path with spaces'],
      input: nil,
      chdir: root,
      timeout: 5
    )

    expect(result).to be_success
    expect(result.stdout).to eq('path with spaces')
    expect(result.stderr).to eq('diagnostic')
    expect(result.exit_code).to eq(0)
  end

  it 'terminates timed-out commands and reports the portable timeout status' do
    result = described_class.new.call(
      [RbConfig.ruby, '-e', 'sleep 30'],
      input: nil,
      chdir: root,
      timeout: 0.05
    )

    expect(result).not_to be_success
    expect(result.timed_out).to be(true)
    expect(result.exit_code).to eq(124)
  end
end
