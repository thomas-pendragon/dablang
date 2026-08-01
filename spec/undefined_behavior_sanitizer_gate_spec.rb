require 'spec_helper'

require 'fileutils'
require 'json'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

require_relative '../lib/dab/undefined_behavior_sanitizer_gate'

module UndefinedBehaviorSanitizerGateSpecSupport
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

  class BuildFailureRunner < Dab::UndefinedBehaviorSanitizerGate::Runner
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
        'dedicated UndefinedBehaviorSanitizer native build',
        %w[make undefined-behavior-sanitizer],
        timeout: 180
      )
    end

    def verify_target_instrumentation; end
    def build_and_verify_canary_binaries; end
    def run_undefined_behavior_canary; end
    def run_native_tool_smoke; end
    def run_unsafe_ffi_capability_smoke; end
    def run_legacy_source_vm_smoke; end

    def execute_required(stage, _command, **_arguments)
      return @result if stage != 'dedicated UndefinedBehaviorSanitizer native build'

      raise Dab::UndefinedBehaviorSanitizerGate::StageFailure.new(
        stage: stage,
        command: %w[make undefined-behavior-sanitizer],
        result: @result,
        timeout: 180
      )
    end
  end
end

describe Dab::UndefinedBehaviorSanitizerGate::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  def result(stdout: '', stderr: '', exit_code: 0, timed_out: false)
    Dab::UndefinedBehaviorSanitizerGate::CommandResult.new(stdout, stderr, exit_code, timed_out)
  end

  def loaded_runner(executor: UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new([]), root: self.root)
    runner = described_class.new(root: root, executor: executor, output: output, error: error)
    runner.send(:load_contract)
    runner
  end

  it 'keeps a distinct fatal UBSan profile for all four native targets on Linux x86_64' do
    contract = Dab::ToolchainPreflight::Contract.load(File.join(root, 'config/supported_toolchain.json'))
    profile = contract.undefined_behavior_sanitizer
    premake = File.binread(File.join(root, 'premake5.lua'))

    expect(contract).to be_valid_structure
    expect(profile.fetch('platform')).to eq('linux-x86_64')
    expect(profile.fetch('compiler')).to eq('clang++-18')
    expect(profile.fetch('c_compiler')).to eq('clang-18')
    expect(profile.fetch('configuration')).to eq('UBSan')
    expect(profile.fetch('build_directory')).to eq('build/undefined-behavior-sanitizer')
    expect(profile.fetch('object_directory')).to eq('build/undefined-behavior-sanitizer/obj/UBSan')
    expect(profile.fetch('binary_directory')).to eq('bin/undefined-behavior-sanitizer')
    expect(profile.fetch('targets').keys).to contain_exactly('cvm', 'cdisasm', 'cdumpcov', 'cffitest')
    expect(profile.fetch('compile_flags')).to include(
      '-fsanitize=undefined',
      '-fno-sanitize-recover=all',
      '-fno-omit-frame-pointer',
      '-fno-optimize-sibling-calls'
    )
    expect(profile.fetch('link_flags')).to eq(['-fsanitize=undefined'])
    expect(premake).to include('fatalwarnings "All"')
    expect(premake).to include('filter "configurations:UBSan"')
    expect(premake).to include(
      'the UndefinedBehaviorSanitizer Premake configuration supports Linux only; ' \
      'the validation gate checks x86_64 separately'
    )
  end

  it 'keeps normal, AddressSanitizer, and UndefinedBehaviorSanitizer state isolated' do
    premake = File.binread(File.join(root, 'premake5.lua'))

    expect(premake).to include('if address_sanitizer and undefined_behavior_sanitizer then')
    expect(premake).to include('undefined_behavior_sanitizer and "build/undefined-behavior-sanitizer"')
    expect(premake).to include('undefined_behavior_sanitizer and "bin/undefined-behavior-sanitizer/"')
    expect(premake).to include(
      'objdir "build/undefined-behavior-sanitizer/obj/%{cfg.buildcfg}/%{prj.name}"'
    )
    expect(premake).to include('address_sanitizer and "build/address-sanitizer"')
    expect(premake).to include('{ "Debug", "Release" }')
  end

  it 'uses runtime volatile operands for the non-product signed-overflow canary' do
    source = File.binread(
      File.join(root, 'test/undefined_behavior_sanitizer/signed_integer_overflow.cpp')
    )

    expect(source.scan('volatile int').length).to eq(2)
    expect(source).to include('std::numeric_limits<int>::max()')
    expect(source).to include('return maximum + one;')
  end

  it 'keeps byte-stream scalar reads alignment-safe without changing native byte order' do
    implementation = File.binread(File.join(root, 'src/cshared/stream.cpp'))
    interface = File.binread(File.join(root, 'src/cshared/stream.h'))
    loader = File.binread(File.join(root, 'src/cvm/bin_load.cpp'))

    expect(implementation.scan('memcpy(&ret, ptr, sizeof(ret));').length).to eq(2)
    expect(interface).to include('memcpy(&ret, data(), sizeof(ret));')
    expect(implementation).not_to match(/\*\(uint(?:16|64)_t \*\)ptr/)
    expect(interface).not_to include('*(T *)data()')
    expect(loader).not_to include('(MethodArgData *)(input.raw_base_data() + ptr)')
    expect(loader.scan(/memcpy\(&(?:return|argument)_data,/).length).to eq(2)
  end

  it 'rejects an ELF binary without non-recovering UBSan handler symbols' do
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stdout: 'ELF symbols without sanitizer')]
    )
    runner = loaded_runner(executor: executor)

    expect { runner.send(:verify_instrumented, 'bin/cvm') }
      .to raise_error(
        Dab::UndefinedBehaviorSanitizerGate::ContractFailure,
        /UndefinedBehaviorSanitizer instrumentation proof failed/
      )
  end

  it 'requires the normal negative control to fail the same handler-symbol proof' do
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stdout: 'UND __ubsan_handle_add_overflow_abort')]
    )
    runner = loaded_runner(executor: executor)

    expect { runner.send(:verify_uninstrumented, 'normal-control') }
      .to raise_error(
        Dab::UndefinedBehaviorSanitizerGate::ContractFailure,
        /negative instrumentation proof failed/
      )
  end

  it 'accepts the exact controlled canary outcome and strict UBSAN_OPTIONS contract' do
    diagnostics = <<~DIAGNOSTICS
      signed_integer_overflow.cpp:8:20: runtime error: signed integer overflow: 2147483647 + 1 cannot be represented in type 'int'
          #0 0x1234
      SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior signed_integer_overflow.cpp:8:20
    DIAGNOSTICS
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: diagnostics, exit_code: 86)]
    )
    runner = loaded_runner(executor: executor)
    runner.instance_variable_set(:@canary, File.join(root, 'canary'))

    expect { runner.send(:run_undefined_behavior_canary) }.not_to raise_error
    expect(executor.calls.first.fetch(:environment).fetch('UBSAN_OPTIONS')).to eq(
      'exitcode=86:halt_on_error=1:print_stacktrace=1:symbolize=0'
    )
  end

  it 'rejects an incomplete or unstable canary result with captured evidence' do
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'runtime error: signed integer overflow', exit_code: 1)]
    )
    runner = loaded_runner(executor: executor)
    runner.instance_variable_set(:@canary, File.join(root, 'canary'))

    expect { runner.send(:run_undefined_behavior_canary) }
      .to raise_error(Dab::UndefinedBehaviorSanitizerGate::ContractFailure) do |failure|
        expect(failure.details).to include(
          'expected exit 86, empty stdout, signed-integer-overflow report, summary, and stack trace'
        )
      end
  end

  it 'attributes a manifest timeout and preserves status 124' do
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new(
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
    expect(error.string).to include(
      'FAILED during test suite manifest validation (timed out after 10 seconds)'
    )
    expect(error.string).to include('exit status: 124')
    expect(error.string).to include('captured stderr: "still validating"')
  end

  it 'fails on a UBSan report even when its process reports success' do
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'runtime error: test report')]
    )
    status = described_class.new(root: root, executor: executor, output: output, error: error).run

    expect(status).to eq(1)
    expect(error.string).to include('FAILED during test suite manifest validation')
    expect(error.string).to include('sanitizer report detected despite a zero exit status')
  end

  it 'rejects unsupported hosts before generation or cleanup' do
    executor = UndefinedBehaviorSanitizerGateSpecSupport::FakeExecutor.new([result, result])
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

  it 'fails closed on a malformed supported-toolchain manifest' do
    Dir.mktmpdir('dab-ubsan-malformed-contract') do |temporary_root|
      FileUtils.mkdir_p(File.join(temporary_root, 'config'))
      File.binwrite(File.join(temporary_root, 'config/supported_toolchain.json'), '{')

      status = described_class.new(root: temporary_root, output: output, error: error).run

      expect(status).to eq(1)
      expect(error.string).to include('FAILED during setup: JSON::ParserError')
    end
  end

  it 'attributes a native build signal and preserves its conventional status' do
    build_result = result(stderr: 'terminated', exit_code: 139)
    status = UndefinedBehaviorSanitizerGateSpecSupport::BuildFailureRunner.new(
      root: root,
      result: build_result,
      output: output,
      error: error
    ).run

    expect(status).to eq(139)
    expect(error.string).to include('FAILED during dedicated UndefinedBehaviorSanitizer native build')
    expect(error.string).to include('exit status: 139')
  end

  it 'cleans only its two owned output trees' do
    Dir.mktmpdir('dab-ubsan-cleanup') do |temporary_root|
      protected = %w[build/normal build/address-sanitizer bin/normal bin/address-sanitizer]
      owned = described_class::OWNED_DIRECTORIES
      (protected + owned).each do |directory|
        FileUtils.mkdir_p(File.join(temporary_root, directory))
        File.binwrite(File.join(temporary_root, directory, 'sentinel'), directory)
      end
      runner = described_class.new(root: temporary_root, output: output, error: error)

      runner.send(:clean_owned_outputs)

      expect(owned).to all(satisfy { |directory| !Dir.exist?(File.join(temporary_root, directory)) })
      expect(protected).to all(satisfy do |directory|
        File.binread(File.join(temporary_root, directory, 'sentinel')) == directory
      end)
    end
  end

  it 'restores an inherited UBSAN_OPTIONS value after a failing nested smoke action' do
    runner = loaded_runner
    original = ENV.fetch('UBSAN_OPTIONS', nil)
    begin
      ENV['UBSAN_OPTIONS'] = 'caller-owned'

      expect do
        runner.send(:with_sanitizer_environment) { raise 'smoke failure' }
      end.to raise_error('smoke failure')
      expect(ENV.fetch('UBSAN_OPTIONS')).to eq('caller-owned')
    ensure
      original.nil? ? ENV.delete('UBSAN_OPTIONS') : ENV['UBSAN_OPTIONS'] = original
    end
  end
end

describe Dab::UndefinedBehaviorSanitizerGate::SystemExecutor do
  let(:root) { File.expand_path('..', __dir__) }

  it 'returns 127 when a command is missing' do
    result = described_class.new.call(
      ['dab-undefined-behavior-sanitizer-command-does-not-exist'],
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

  it 'kills a timed-out process group even when the leader exits before its child' do
    skip 'POSIX process-group behavior is not available on Windows' if Gem.win_platform?

    script = <<~RUBY
      trap('TERM') { exit! 0 }
      fork do
        trap('TERM', 'IGNORE')
        sleep 30
      end
      sleep 30
    RUBY
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = described_class.new.call([RbConfig.ruby, '-e', script], chdir: root, timeout: 0.05)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(result.exit_code).to eq(124)
    expect(result.timed_out).to be(true)
    expect(elapsed).to be < 3
  end
end

describe 'UndefinedBehaviorSanitizer gate repository contract' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'uses one documented Rake command in the manifest and blocking CI job' do
    manifest = JSON.parse(File.binread(File.join(root, 'config/test_suites.json')))
    entries = manifest.fetch('suites').select do |suite|
      suite['id'] == 'rake-undefined-behavior-sanitizer'
    end
    documentation = File.binread(File.join(root, 'docs/undefined-behavior-sanitizer.md'))
    workflow = File.binread(File.join(root, '.github/workflows/ruby.yml'))

    expect(entries.length).to eq(1)
    expect(entries.first.fetch('command')).to eq(
      %w[bundle exec rake undefined_behavior_sanitizer_spec]
    )
    expect(entries.first.fetch('in_complete_gate')).to be(false)
    normalized_documentation = documentation.gsub("\r\n", "\n")
    expect(normalized_documentation).to include(
      "```shell\nbundle exec rake undefined_behavior_sanitizer_spec\n```"
    )
    expect(workflow.scan('run: bundle exec rake undefined_behavior_sanitizer_spec').length).to eq(1)
    expect(workflow).not_to include('continue-on-error')
  end
end
