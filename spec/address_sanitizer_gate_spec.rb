require 'spec_helper'

require 'json'
require 'rbconfig'
require 'stringio'

require_relative '../lib/dab/address_sanitizer_gate'

module AddressSanitizerGateSpecSupport
  class FakeExecutor
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def call(command, chdir:, timeout:, environment: {})
      calls << {command: command, chdir: chdir, timeout: timeout, environment: environment}
      @results.shift || raise('unexpected command')
    end
  end

  class BuildFailureRunner < Dab::AddressSanitizerGate::Runner
    def initialize(result:, **arguments)
      super(**arguments)
      @result = result
    end

  private

    def load_contract; end
    def validate_profile; end
    def validate_tools; end
    def clean_owned_outputs; end
    def generate_build; end
    def validate_generated_build; end

    def build_targets
      execute_required(
        'dedicated AddressSanitizer native build',
        %w[make address-sanitizer],
        timeout: 180
      )
    end

    def verify_target_instrumentation; end
    def run_memory_error_canary; end
    def run_native_tool_smoke; end
    def characterize_legacy_smoke_leak; end
    def run_legacy_source_vm_smoke; end

    def execute_required(stage, _command, **_arguments)
      return @result if stage != 'dedicated AddressSanitizer native build'

      raise Dab::AddressSanitizerGate::StageFailure.new(
        stage: stage,
        command: %w[make address-sanitizer],
        result: @result,
        timeout: 180
      )
    end
  end
end

describe Dab::AddressSanitizerGate::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  def result(stdout: '', stderr: '', exit_code: 0, timed_out: false)
    Dab::AddressSanitizerGate::CommandResult.new(stdout, stderr, exit_code, timed_out)
  end

  it 'keeps the committed profile separate, fatal, address-instrumented, and Linux x86_64-only' do
    contract = Dab::ToolchainPreflight::Contract.load(File.join(root, 'config/supported_toolchain.json'))
    profile = contract.address_sanitizer
    premake = File.binread(File.join(root, 'premake5.lua'))

    expect(contract).to be_valid_structure
    expect(profile.fetch('platform')).to eq('linux-x86_64')
    expect(profile.fetch('compiler')).to eq('clang++-18')
    expect(profile.fetch('build_directory')).to eq('build/address-sanitizer')
    expect(profile.fetch('object_directory')).to eq('build/address-sanitizer/obj/ASan')
    expect(profile.fetch('binary_directory')).to eq('bin/address-sanitizer')
    expect(profile.fetch('targets').keys).to contain_exactly('cvm', 'cdisasm', 'cdumpcov', 'cffitest')
    expect(profile.fetch('compile_flags')).to include(
      '-fsanitize=address',
      '-fsanitize-address-use-after-scope',
      '-fno-omit-frame-pointer',
      '-fno-optimize-sibling-calls'
    )
    expect(profile.fetch('link_flags')).to include('-fsanitize=address')
    expect(profile.fetch('leak_detection')).to be(true)
    expect(premake).to include('fatalwarnings "All"')
    expect(premake).to include('address_sanitizer and { "ASan" }')
    expect(premake).to include('filter "configurations:ASan"')
  end

  it 'keeps normal build state and outputs distinct from the AddressSanitizer namespace' do
    premake = File.binread(File.join(root, 'premake5.lua'))

    expect(premake).to include('address_sanitizer and "build/address-sanitizer"')
    expect(premake).to include('address_sanitizer and "bin/address-sanitizer/"')
    expect(premake).to include('objdir "build/address-sanitizer/obj/%{cfg.buildcfg}/%{prj.name}"')
  end

  it 'rejects a binary when instrumentation metadata is absent' do
    executor = AddressSanitizerGateSpecSupport::FakeExecutor.new([result(stdout: 'ELF symbols without sanitizer')])
    runner = described_class.new(root: root, executor: executor, output: output, error: error)
    runner.send(:load_contract)

    expect { runner.send(:verify_instrumented, 'bin/cvm') }
      .to raise_error(
        Dab::AddressSanitizerGate::ContractFailure,
        /AddressSanitizer instrumentation proof failed/
      )
  end

  it 'attributes a manifest timeout and preserves status 124' do
    executor = AddressSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'still validating', exit_code: 124, timed_out: true)]
    )
    status = described_class.new(
      root: root,
      executor: executor,
      output: output,
      error: error,
      host_os: 'linux-gnu',
      host_cpu: 'x86_64'
    ).run

    expect(status).to eq(124)
    expect(error.string).to include('FAILED during test suite manifest validation (timed out after 10 seconds)')
    expect(error.string).to include('exit status: 124')
  end

  it 'attributes a missing profile compiler and returns 127' do
    executor = AddressSanitizerGateSpecSupport::FakeExecutor.new(
      [result, result, result(stderr: 'missing', exit_code: 127)]
    )
    status = described_class.new(
      root: root,
      executor: executor,
      output: output,
      error: error,
      host_os: 'linux-gnu',
      host_cpu: 'x86_64'
    ).run

    expect(status).to eq(127)
    expect(error.string).to include('FAILED during AddressSanitizer C++ compiler precondition')
    expect(error.string).to include('captured stderr: "missing"')
  end

  it 'fails on a sanitizer report even when its process reports success' do
    executor = AddressSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'ERROR: AddressSanitizer: test report')]
    )
    status = described_class.new(root: root, executor: executor, output: output, error: error).run

    expect(status).to eq(1)
    expect(error.string).to include('FAILED during test suite manifest validation')
    expect(error.string).to include('sanitizer report detected despite a zero exit status')
  end

  it 'rejects unsupported hosts before generation or cleanup' do
    executor = AddressSanitizerGateSpecSupport::FakeExecutor.new([result, result])
    status = described_class.new(
      root: root,
      executor: executor,
      output: output,
      error: error,
      host_os: 'linux-gnu',
      host_cpu: 'aarch64'
    ).run

    expect(status).to eq(1)
    expect(error.string).to include('supported linux-x86_64; current linux-arm64')
    expect(executor.calls.length).to eq(2)
  end

  it 'attributes a native build signal and preserves its conventional status' do
    build_result = result(stderr: 'terminated', exit_code: 139)
    status = AddressSanitizerGateSpecSupport::BuildFailureRunner.new(
      root: root,
      result: build_result,
      output: output,
      error: error
    ).run

    expect(status).to eq(139)
    expect(error.string).to include('FAILED during dedicated AddressSanitizer native build')
    expect(error.string).to include('exit status: 139')
  end

  it 'records the exact leak-only boundary without suppressing the known dangling-pointer source' do
    contract = JSON.parse(File.binread(File.join(root, 'test/address_sanitizer/legacy_smoke_leak_contract.json')))
    source = File.binread(File.join(root, 'src/cvm/main.cpp'))
    documentation = File.binread(File.join(root, 'docs/address-sanitizer.md'))

    expect(contract.fetch('expected_summary')).to eq(
      'SUMMARY: AddressSanitizer: 160 byte(s) leaked in 4 allocation(s).'
    )
    expect(source).to include('copy.data.intptr = (void *)value.string().c_str();')
    expect(documentation).to include('neither fixes nor suppresses that path')
    expect(documentation).to include('only leak detection disabled')
  end
end

describe Dab::AddressSanitizerGate::SystemExecutor do
  let(:root) { File.expand_path('..', __dir__) }

  it 'returns 127 when a command is missing' do
    result = described_class.new.call(
      ['dab-address-sanitizer-command-does-not-exist'],
      chdir: root,
      timeout: 1
    )

    expect(result.exit_code).to eq(127)
    expect(result).not_to be_success
  end

  it 'maps a native signal to 128 plus the signal number' do
    skip 'POSIX signal status is covered on the supported Linux profile and macOS' if Gem.win_platform?

    result = described_class.new.call(
      [RbConfig.ruby, '-e', 'Process.kill("TERM", Process.pid)'],
      chdir: root,
      timeout: 1
    )

    expect(result.exit_code).to eq(143)
    expect(result).not_to be_success
  end

  it 'terminates timed-out process groups and returns 124' do
    result = described_class.new.call(
      [RbConfig.ruby, '-e', 'sleep 30'],
      chdir: root,
      timeout: 0.05
    )

    expect(result.exit_code).to eq(124)
    expect(result.timed_out).to be(true)
  end
end

describe 'AddressSanitizer gate repository contract' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'uses one documented Rake command in the manifest and the blocking CI job' do
    manifest = JSON.parse(File.binread(File.join(root, 'config/test_suites.json')))
    entries = manifest.fetch('suites').select { |suite| suite['id'] == 'rake-address-sanitizer' }
    documentation = File.binread(File.join(root, 'docs/address-sanitizer.md'))
    workflow = File.binread(File.join(root, '.github/workflows/ruby.yml'))

    expect(entries.length).to eq(1)
    expect(entries.first.fetch('command')).to eq(%w[bundle exec rake address_sanitizer_spec])
    expect(entries.first.fetch('in_complete_gate')).to be(false)
    normalized_documentation = documentation.gsub("\r\n", "\n")
    expect(normalized_documentation).to include("```shell\nbundle exec rake address_sanitizer_spec\n```")
    expect(workflow.scan('run: bundle exec rake address_sanitizer_spec').length).to eq(1)
    expect(workflow).not_to include('continue-on-error')
  end
end
