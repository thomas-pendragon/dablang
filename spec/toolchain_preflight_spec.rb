require 'spec_helper'

require 'digest'
require 'tmpdir'

require_relative '../lib/dab/toolchain_preflight'

module ToolchainPreflightSpecSupport
  class FakeToolchainProbe
    attr_reader :captures

    def initialize(results)
      @results = results
      @captures = []
    end

    def capture(command, *arguments)
      captures << [command, arguments]
      @results.fetch(command) do
        Dab::ToolchainPreflight::CommandResult.new(command, nil, '', '', false)
      end
    end
  end
end

describe Dab::ToolchainPreflight::Runner do
  project_root = File.expand_path('..', __dir__)
  contract = Dab::ToolchainPreflight::Contract.load(File.join(project_root, 'config/supported_toolchain.json'))

  def command_result(command, path, output, success = true)
    Dab::ToolchainPreflight::CommandResult.new(command, path, output, '', success)
  end

  def successful_probe(contract, platform, premake_command: nil)
    premake_command ||= platform.fetch('premake_command')
    ToolchainPreflightSpecSupport::FakeToolchainProbe.new(
      'bundle' => command_result('bundle', '/tools/bundle', "Bundler version #{contract.bundler_version}\n"),
      premake_command => command_result(premake_command, '/tools/premake5', "premake5 (Premake Build Script Generator) #{contract.premake_version}\n"),
      platform.fetch('build_driver') => command_result(platform.fetch('build_driver'), '/tools/make', "GNU Make 4.4.1\n"),
      platform.fetch('compiler') => command_result(platform.fetch('compiler'), '/tools/compiler', "compiler version 18.1.8\n"),
      platform.fetch('clang_format') => command_result(platform.fetch('clang_format'), '/tools/clang-format', "clang-format version 18.1.8\n")
    )
  end

  def runner(contract:, platform_name:, ruby_version:, probe:, environment: {})
    platform = contract.platforms.fetch(platform_name)
    described_class.new(
      root: File.expand_path('..', __dir__),
      contract: contract,
      repository_contract: double(errors: []),
      probe: probe,
      environment: environment,
      host_os: platform.fetch('os'),
      host_cpu: platform.fetch('architecture'),
      ruby_version: ruby_version,
      ruby_path: '/tools/ruby'
    )
  end

  {
    'linux-x86_64' => '3.4.9',
    'macos-x86_64' => '3.3.12',
    'windows-x86_64' => '3.3.12',
  }.each do |platform_name, ruby_version|
    it "accepts the simulated #{platform_name} toolchain" do
      platform = contract.platforms.fetch(platform_name)
      result = runner(
        contract: contract,
        platform_name: platform_name,
        ruby_version: ruby_version,
        probe: successful_probe(contract, platform)
      ).run

      expect(result).to be_success
      expect(result.output).to start_with("supported-toolchain preflight: OK platform=#{platform_name} ruby=#{ruby_version} ruby_path=/tools/ruby")
      expect(result.output).to include("bundler=#{contract.bundler_version}")
      expect(result.output).to include("premake=#{contract.premake_version}")
      expect(result.output).to include("action=#{contract.premake_action} driver=#{platform.fetch('build_driver')}@4.4.1")
      expect(result.output).to end_with("clang-format=#{platform.fetch('clang_format')}@18.1.8 clang-format_path=/tools/clang-format\n")
    end
  end

  it 'uses the selected Premake and clang-format paths' do
    platform = contract.platforms.fetch('linux-x86_64')
    environment = {
      'PREMAKE' => '/selected/premake',
      'CLANG_FORMAT' => '/selected/clang-format',
    }
    probe = successful_probe(contract, platform, premake_command: '/selected/premake')
    probe_results = probe.instance_variable_get(:@results)
    probe_results['/selected/premake'].path = '/selected/premake'
    selected_clang_format = probe_results.delete('clang-format')
    selected_clang_format.command = '/selected/clang-format'
    selected_clang_format.path = '/selected/clang-format'
    probe_results['/selected/clang-format'] = selected_clang_format

    result = runner(
      contract: contract,
      platform_name: 'linux-x86_64',
      ruby_version: platform.fetch('ruby_versions').first,
      probe: probe,
      environment: environment
    ).run

    expect(result).to be_success
    expect(result.output).to include('premake_path=/selected/premake')
    expect(result.output).to include('clang-format_path=/selected/clang-format')
  end

  it 'accepts an exact stable Premake version from the contract' do
    stable_data = JSON.parse(JSON.generate(contract.data))
    stable_data['premake_version'] = '5.0.0'
    stable_contract = Dab::ToolchainPreflight::Contract.new(stable_data)
    platform = stable_contract.platforms.fetch('linux-x86_64')

    result = runner(
      contract: stable_contract,
      platform_name: 'linux-x86_64',
      ruby_version: platform.fetch('ruby_versions').first,
      probe: successful_probe(stable_contract, platform)
    ).run

    expect(result).to be_success
    expect(result.output).to include('premake=5.0.0')
  end

  it 'reports missing commands and wrong exact versions together' do
    platform = contract.platforms.fetch('linux-x86_64')
    results = successful_probe(contract, platform).instance_variable_get(:@results)
    results.delete('make')
    results['bundle'] = command_result('bundle', '/tools/bundle', "Bundler version 0.0.0\n")
    results['premake5'] = command_result('premake5', '/tools/premake5', "premake5 0.0.0-beta0\n")

    result = runner(
      contract: contract,
      platform_name: 'linux-x86_64',
      ruby_version: platform.fetch('ruby_versions').first,
      probe: ToolchainPreflightSpecSupport::FakeToolchainProbe.new(results)
    ).run

    expect(result).not_to be_success
    expect(result.output).to start_with("supported-toolchain preflight: FAILED\n")
    expect(result.errors).to include("bundler at /tools/bundle is 0.0.0; install bundler #{contract.bundler_version}")
    expect(result.errors).to include("premake at /tools/premake5 is 0.0.0-beta0; install premake #{contract.premake_version}")
    expect(result.errors).to include('driver executable is missing; install it or select its executable with PATH')
  end

  it 'rejects an unsupported Ruby without skipping other probes' do
    platform = contract.platforms.fetch('macos-x86_64')
    probe = successful_probe(contract, platform)
    result = runner(
      contract: contract,
      platform_name: 'macos-x86_64',
      ruby_version: '0.0.0',
      probe: probe
    ).run

    expect(result).not_to be_success
    expect(result.errors).to include("unsupported Ruby 0.0.0 for macos-x86_64; use #{platform.fetch('ruby_versions').join(' or ')}")
    expect(result.errors.length).to eq(1)
    expect(probe.captures).to eq(
      [
        ['bundle', ['--version']],
        [platform.fetch('premake_command'), ['--version']],
        [platform.fetch('build_driver'), ['--version']],
        [platform.fetch('compiler'), ['--version']],
        [platform.fetch('clang_format'), ['--version']],
      ]
    )
  end

  it 'rejects unsupported operating systems and architectures' do
    result = described_class.new(
      root: project_root,
      contract: contract,
      repository_contract: double(errors: []),
      probe: ToolchainPreflightSpecSupport::FakeToolchainProbe.new(
        'bundle' => command_result('bundle', '/tools/bundle', "Bundler version #{contract.bundler_version}\n")
      ),
      environment: {},
      host_os: 'freebsd',
      host_cpu: 'arm64',
      ruby_version: contract.default_ruby_version
    ).run

    expect(result).not_to be_success
    expect(result.errors).to include('unsupported platform freebsd-arm64; use one of linux-x86_64, macos-x86_64, windows-x86_64')
  end

  it 'rejects a build-driver override outside the supported gmake contract' do
    platform = contract.platforms.fetch('linux-x86_64')
    result = runner(
      contract: contract,
      platform_name: 'linux-x86_64',
      ruby_version: platform.fetch('ruby_versions').first,
      probe: successful_probe(contract, platform),
      environment: {'TOOLSET' => 'vs2022'}
    ).run

    expect(result).not_to be_success
    expect(result.errors).to include("unsupported TOOLSET; unset it or use #{contract.premake_action}")
  end

  it 'does not mutate files while probing' do
    before = Dir.glob(File.join(project_root, '{config,lib,script}', '**', '*')).select { |path| File.file?(path) }.sort.map do |path|
      [path, Digest::SHA256.file(path).hexdigest]
    end
    platform = contract.platforms.fetch('linux-x86_64')

    runner(
      contract: contract,
      platform_name: 'linux-x86_64',
      ruby_version: platform.fetch('ruby_versions').first,
      probe: successful_probe(contract, platform)
    ).run

    after = before.map { |path, _digest| [path, Digest::SHA256.file(path).hexdigest] }
    expect(after).to eq(before)
  end

  it 'reports a missing manifest without raising' do
    Dir.mktmpdir('dab-missing-toolchain-manifest') do |root|
      result = described_class.new(
        root: root,
        probe: ToolchainPreflightSpecSupport::FakeToolchainProbe.new({}),
        environment: {},
        host_os: 'linux',
        host_cpu: 'x86_64',
        ruby_version: RUBY_VERSION
      ).run

      expect(result).not_to be_success
      expect(result.errors).to eq(
        ['config/supported_toolchain.json is missing; restore it from the repository']
      )
    end
  end

  it 'reports an invalid manifest without raising' do
    Dir.mktmpdir('dab-invalid-toolchain-manifest') do |root|
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config/supported_toolchain.json'), '{')

      result = described_class.new(
        root: root,
        probe: ToolchainPreflightSpecSupport::FakeToolchainProbe.new({}),
        environment: {},
        host_os: 'linux',
        host_cpu: 'x86_64',
        ruby_version: RUBY_VERSION
      ).run

      expect(result).not_to be_success
      expect(result.errors).to eq(
        ['config/supported_toolchain.json is invalid JSON; fix its syntax']
      )
    end
  end

  it 'reports a structurally invalid manifest without raising' do
    profile_drift = JSON.parse(File.binread(File.join(project_root, 'config/supported_toolchain.json')))
    profile_drift.fetch('profiles').fetch('address_sanitizer')['unexpected'] = true
    invalid_manifests = [
      {},
      {
        'schema_version' => 1,
        'default_ruby_version' => '3.3.12',
        'bundler_version' => '2.7.2',
        'premake_version' => '5.0.0-beta8',
        'premake_action' => 'gmake',
        'platforms' => [],
      },
      profile_drift,
    ]

    invalid_manifests.each do |manifest|
      Dir.mktmpdir('dab-invalid-toolchain-structure') do |root|
        FileUtils.mkdir_p(File.join(root, 'config'))
        File.write(File.join(root, 'config/supported_toolchain.json'), JSON.generate(manifest))

        result = described_class.new(
          root: root,
          probe: ToolchainPreflightSpecSupport::FakeToolchainProbe.new({}),
          environment: {},
          host_os: 'linux',
          host_cpu: 'x86_64',
          ruby_version: RUBY_VERSION
        ).run

        expect(result).not_to be_success
        expect(result.output).to eq(
          "supported-toolchain preflight: FAILED\n" \
          "- config/supported_toolchain.json does not match the required structure; restore it from the repository\n"
        )
      end
    end
  end
end
