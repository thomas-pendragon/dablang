require 'spec_helper'

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'

require_relative '../lib/dab/combined_sanitizer_gate'

module CombinedSanitizerGateSpecSupport
  class FakeExecutor
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def call(command, chdir:, timeout:, environment: {})
      @calls << {command: command, chdir: chdir, timeout: timeout, environment: environment}
      @results.shift || raise('unexpected command')
    end
  end
end

describe Dab::CombinedSanitizerGate::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  def result(stdout: '', stderr: '', exit_code: 0, timed_out: false)
    Dab::UndefinedBehaviorSanitizerGate::CommandResult.new(
      stdout,
      stderr,
      exit_code,
      timed_out
    )
  end

  def runner(executor, **arguments)
    described_class.new(
      root: root,
      executor: executor,
      output: output,
      error: error,
      host_os: 'linux-gnu',
      host_cpu: 'x86_64',
      **arguments
    )
  end

  it 'runs AddressSanitizer then UndefinedBehaviorSanitizer exactly once' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [
        result(stdout: "AddressSanitizer gate: PASSED\n"),
        result(stdout: "UndefinedBehaviorSanitizer gate: PASSED\n"),
      ]
    )

    status = runner(executor).run

    expect(status).to eq(0)
    expect(executor.calls.map { |call| call.fetch(:command) }).to eq(
      [
        %w[bundle exec rake address_sanitizer_spec],
        %w[bundle exec rake undefined_behavior_sanitizer_spec],
      ]
    )
    expect(executor.calls.map { |call| call.fetch(:timeout) }).to eq([600, 600])
    expect(output.string).to include(
      'Combined sanitizer gate: PASSED (AddressSanitizer then UndefinedBehaviorSanitizer)'
    )
    expect(error.string).to be_empty
  end

  it 'fails fast, attributes AddressSanitizer, and preserves a nonzero status' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'address failure', exit_code: 86)]
    )

    status = runner(executor).run

    expect(status).to eq(86)
    expect(executor.calls.length).to eq(1)
    expect(error.string).to include('address failure')
    expect(error.string).to include('Combined sanitizer gate: FAILED in AddressSanitizer')
    expect(error.string).to include(
      'UndefinedBehaviorSanitizer: NOT RUN (fail-fast after AddressSanitizer)'
    )
    expect(output.string).not_to include('Combined sanitizer gate: PASSED')
  end

  it 'attributes UndefinedBehaviorSanitizer and preserves its signal status' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [
        result(stdout: "AddressSanitizer gate: PASSED\n"),
        result(stderr: 'terminated', exit_code: 143),
      ]
    )

    status = runner(executor).run

    expect(status).to eq(143)
    expect(executor.calls.length).to eq(2)
    expect(error.string).to include('Combined sanitizer gate: FAILED in UndefinedBehaviorSanitizer')
    expect(error.string).to include('exit status: 143')
  end

  it 'preserves combined timeout status and does not start the next gate' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'still running', exit_code: 124, timed_out: true)]
    )

    status = runner(executor).run

    expect(status).to eq(124)
    expect(executor.calls.length).to eq(1)
    expect(error.string).to include('timed out after 600 seconds')
    expect(error.string).to include('exit status: 124')
  end

  it 'preserves missing-command status and captured diagnostics' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stderr: 'No such file or directory', exit_code: 127)]
    )

    status = runner(executor).run

    expect(status).to eq(127)
    expect(error.string).to include('No such file or directory')
    expect(error.string).to include('exit status: 127')
  end

  it 'rejects a partial zero-exit child run without its completion marker' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [result(stdout: "AddressSanitizer gate: instrumentation metadata proof\n")]
    )

    status = runner(executor).run

    expect(status).to eq(1)
    expect(executor.calls.length).to eq(1)
    expect(error.string).to include(
      'exited successfully without "AddressSanitizer gate: PASSED"'
    )
    expect(output.string).not_to include('Combined sanitizer gate: PASSED')
  end

  it 'rejects unsupported hosts before either sanitizer starts' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new([])
    status = described_class.new(
      root: root,
      executor: executor,
      output: output,
      error: error,
      host_os: 'darwin',
      host_cpu: 'x86_64'
    ).run

    expect(status).to eq(1)
    expect(executor.calls).to be_empty
    expect(error.string).to include('supported linux-x86_64; current macos-x86_64')
  end

  it 'does not clean either child gate output tree itself' do
    executor = CombinedSanitizerGateSpecSupport::FakeExecutor.new(
      [
        result(stdout: "AddressSanitizer gate: PASSED\n"),
        result(stdout: "UndefinedBehaviorSanitizer gate: PASSED\n"),
      ]
    )
    sentinels = %w[
      build/address-sanitizer/combined-gate-sentinel
      bin/address-sanitizer/combined-gate-sentinel
      build/undefined-behavior-sanitizer/combined-gate-sentinel
      bin/undefined-behavior-sanitizer/combined-gate-sentinel
    ]
    begin
      sentinels.each do |relative_path|
        path = File.join(root, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, relative_path)
      end

      expect(runner(executor).run).to eq(0)
      expect(sentinels).to all(satisfy { |path| File.file?(File.join(root, path)) })
    ensure
      sentinels.each { |path| FileUtils.rm_f(File.join(root, path)) }
    end
  end
end

describe Dab::CombinedSanitizerGate::Contract do
  let(:root) { File.expand_path('..', __dir__) }
  let(:contract_path) { File.join(root, 'config/combined_sanitizer_gate.json') }
  let(:toolchain_path) { File.join(root, 'config/supported_toolchain.json') }
  let(:toolchain) { Dab::ToolchainPreflight::Contract.load(toolchain_path) }

  def contract_data
    JSON.parse(File.binread(contract_path))
  end

  def validate(data, validation_root: root)
    described_class.new(data).validate!(root: validation_root, toolchain: toolchain)
  end

  def with_contract_repository
    Dir.mktmpdir('dab-combined-sanitizer-contract') do |temporary_root|
      %w[config .github/workflows test/address_sanitizer test/undefined_behavior_sanitizer test/native].each do |directory|
        FileUtils.mkdir_p(File.join(temporary_root, directory))
      end
      FileUtils.cp(File.join(root, 'config/test_suites.json'), File.join(temporary_root, 'config'))
      FileUtils.cp(File.join(root, '.github/workflows/ruby.yml'), File.join(temporary_root, '.github/workflows'))
      Dab::CombinedSanitizerGate::Contract::EXPECTED_ARTIFACTS.values.flatten.grep(/\Asource:/).each do |artifact|
        relative_path = artifact.split(':', 2).last
        destination = File.join(temporary_root, relative_path)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(root, relative_path), destination)
      end
      yield temporary_root
    end
  end

  it 'accepts the committed exact order, trusted artifact sets, profiles, manifest, and CI policy' do
    expect { validate(contract_data) }.not_to raise_error
  end

  it 'rejects reordered, omitted, and duplicated sanitizer execution entries' do
    reordered = contract_data
    reordered.fetch('validations').reverse!
    omitted = contract_data
    omitted.fetch('validations').pop
    duplicated = contract_data
    duplicated.fetch('validations')[1] = duplicated.fetch('validations').first.dup

    [reordered, omitted, duplicated].each do |data|
      expect { validate(data) }.to raise_error(
        Dab::CombinedSanitizerGate::ContractFailure,
        /validation order must be address-sanitizer then undefined-behavior-sanitizer/
      )
    end
  end

  it 'rejects malformed schema, timeout, profile, and output-directory drift' do
    malformed = contract_data
    malformed['schema_version'] = 2
    timeout_drift = contract_data
    timeout_drift.fetch('validations').first['timeout_seconds'] = 1
    profile_drift = contract_data
    profile_drift.fetch('validations').first['profile'] = 'undefined_behavior_sanitizer'
    output_drift = contract_data
    output_drift.fetch('validations').first['owned_directories'] = ['build', 'bin']

    expect { validate(malformed) }.to raise_error(
      Dab::CombinedSanitizerGate::ContractFailure,
      /schema_version must be 1/
    )
    expect { validate(timeout_drift) }.to raise_error(
      Dab::CombinedSanitizerGate::ContractFailure,
      /timeout_seconds must remain 600/
    )
    expect { validate(profile_drift) }.to raise_error(
      Dab::CombinedSanitizerGate::ContractFailure,
      /address-sanitizer command must match its independent gate/
    )
    expect { validate(output_drift) }.to raise_error(
      Dab::CombinedSanitizerGate::ContractFailure,
      /address-sanitizer owned directories must match its independent gate/
    )
  end

  it 'rejects missing trusted artifact sources before execution' do
    with_contract_repository do |temporary_root|
      FileUtils.rm(File.join(temporary_root, 'test/native/string_intptr_lifetime.cpp'))

      expect { validate(contract_data, validation_root: temporary_root) }.to raise_error(
        Dab::CombinedSanitizerGate::ContractFailure,
        /trusted source is missing: test\/native\/string_intptr_lifetime.cpp/
      )
    end
  end

  it 'rejects manifest command drift' do
    with_contract_repository do |temporary_root|
      path = File.join(temporary_root, 'config/test_suites.json')
      manifest = JSON.parse(File.binread(path))
      combined = manifest.fetch('suites').find { |suite| suite['id'] == 'rake-combined-sanitizer' }
      combined['command'] = %w[bundle exec rake address_sanitizer_spec]
      File.binwrite(path, JSON.pretty_generate(manifest))

      expect { validate(contract_data, validation_root: temporary_root) }.to raise_error(
        Dab::CombinedSanitizerGate::ContractFailure,
        /test-suite manifest command drifted for rake-combined-sanitizer/
      )
    end
  end

  it 'rejects duplicate child execution or a redundant combined CI invocation' do
    with_contract_repository do |temporary_root|
      path = File.join(temporary_root, '.github/workflows/ruby.yml')
      workflow = File.binread(path)
      workflow = workflow.sub(
        'run: bundle exec rake undefined_behavior_sanitizer_spec',
        "run: bundle exec rake undefined_behavior_sanitizer_spec\n" \
        "      - name: Redundant combined gate\n" \
        '        run: bundle exec rake combined_sanitizer_spec'
      )
      workflow = workflow.sub(
        'run: bundle exec rake address_sanitizer_spec',
        "run: bundle exec rake address_sanitizer_spec\n" \
        "      - name: Duplicate AddressSanitizer\n" \
        '        run: bundle exec rake address_sanitizer_spec'
      )
      File.binwrite(path, workflow)

      expect { validate(contract_data, validation_root: temporary_root) }.to raise_error(
        Dab::CombinedSanitizerGate::ContractFailure
      ) do |failure|
        expect(failure.details).to include('CI must invoke AddressSanitizer exactly once, got 2')
        expect(failure.details).to include(
          'CI must contract-check the combined gate without rerunning both sanitizer jobs'
        )
      end
    end
  end
end

describe 'Combined sanitizer gate repository contract' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'uses one documented root command and keeps it outside ordinary and CI gates' do
    manifest = JSON.parse(File.binread(File.join(root, 'config/test_suites.json')))
    entries = manifest.fetch('suites').select { |suite| suite['id'] == 'rake-combined-sanitizer' }
    documentation = File.binread(File.join(root, 'docs/combined-sanitizer.md')).gsub("\r\n", "\n")
    workflow = File.binread(File.join(root, '.github/workflows/ruby.yml'))

    expect(entries.length).to eq(1)
    expect(entries.first.fetch('command')).to eq(%w[bundle exec rake combined_sanitizer_spec])
    expect(entries.first.fetch('in_complete_gate')).to be(false)
    expect(documentation).to include("```shell\nbundle exec rake combined_sanitizer_spec\n```")
    expect(workflow).not_to include('run: bundle exec rake combined_sanitizer_spec')
    expect(workflow.scan('run: bundle exec rake address_sanitizer_spec').length).to eq(1)
    expect(workflow.scan('run: bundle exec rake undefined_behavior_sanitizer_spec').length).to eq(1)
  end
end
