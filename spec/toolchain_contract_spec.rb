require 'spec_helper'

require 'fileutils'
require 'tmpdir'

require_relative '../lib/dab/toolchain_preflight'

describe Dab::ToolchainPreflight::RepositoryContract do
  project_root = File.expand_path('..', __dir__)

  def with_contract_repository(project_root)
    Dir.mktmpdir('dab-toolchain-contract') do |root|
      %w[
        .github/workflows/ruby.yml
        .ruby-version
        Gemfile.lock
        Rakefile
        config/supported_toolchain.json
      ].each do |relative_path|
        source = File.join(project_root, relative_path)
        target = File.join(root, relative_path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
      end
      contract = Dab::ToolchainPreflight::Contract.load(File.join(root, 'config/supported_toolchain.json'))
      yield(root, contract)
    end
  end

  it 'keeps four job definitions for five normal runs plus one AddressSanitizer run consistent' do
    with_contract_repository(project_root) do |root, contract|
      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to be_empty
    end
  end

  it 'detects AddressSanitizer runner, compiler, command, and blocking drift' do
    with_contract_repository(project_root) do |root, contract|
      workflow_path = File.join(root, '.github/workflows/ruby.yml')
      workflow = File.read(workflow_path)
      workflow = workflow.sub('runs-on: ubuntu-24.04', 'runs-on: ubuntu-latest')
      workflow = workflow.sub('CXX: clang++-18', 'CXX: clang++')
      workflow = workflow.sub(
        'run: bundle exec rake address_sanitizer_spec',
        "continue-on-error: true\n        run: bundle exec rake"
      )
      File.write(workflow_path, workflow)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include('CI job address-sanitizer must run on ubuntu-24.04')
      expect(errors).to include(
        'CI job address-sanitizer compiler and Premake environment must match the AddressSanitizer profile'
      )
      expect(errors).to include('CI job address-sanitizer steps must remain blocking')
      expect(errors).to include('CI job address-sanitizer must run bundle exec rake address_sanitizer_spec')
    end
  end

  it 'detects Ruby and Bundler metadata drift' do
    with_contract_repository(project_root) do |root, contract|
      File.write(File.join(root, '.ruby-version'), "9.9.9\n")
      lockfile = File.read(File.join(root, 'Gemfile.lock')).sub(/BUNDLED WITH\s*\n\s+\S+/, "BUNDLED WITH\n   9.9.9")
      File.write(File.join(root, 'Gemfile.lock'), lockfile)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include(".ruby-version is \"9.9.9\"; set it to the supported default #{contract.default_ruby_version}")
      expect(errors).to include("Gemfile.lock records Bundler 9.9.9; regenerate it with Bundler #{contract.bundler_version}")
    end
  end

  it 'detects workflow matrix, pinned-tool, and step-order drift' do
    with_contract_repository(project_root) do |root, contract|
      workflow_path = File.join(root, '.github/workflows/ruby.yml')
      workflow = File.read(workflow_path)
      workflow = workflow.sub("['3.3.12', '3.4.9', '4.0.5']", "['3.3.12']")
      workflow = workflow.gsub('premake-5.0.0-beta8-linux.tar.gz', 'premake-5.0.0-beta7-linux.tar.gz')
      workflow = workflow.sub('run: ruby script/complete_gate.rb', 'run: bundle exec rake')
      File.write(workflow_path, workflow)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include('CI job test Ruby matrix must match the supported-toolchain manifest')
      expect(errors).to include('CI job test must install Premake 5.0.0-beta8 from premake-5.0.0-beta8-linux.tar.gz')
      expect(errors).to include('CI job test must run ruby script/complete_gate.rb')
    end
  end

  it 'detects an additional workflow trigger' do
    with_contract_repository(project_root) do |root, contract|
      workflow_path = File.join(root, '.github/workflows/ruby.yml')
      workflow = File.read(workflow_path).sub(
        "    branches: [master]\n",
        "    branches: [master]\n  workflow_dispatch:\n"
      )
      File.write(workflow_path, workflow)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include('CI trigger drifted; keep the workflow pull-request-only for master')
    end
  end

  it 'detects Rake tool-selection drift' do
    with_contract_repository(project_root) do |root, contract|
      rakefile_path = File.join(root, 'Rakefile')
      rakefile = File.read(rakefile_path).sub("ENV['TOOLSET'] || 'gmake'", "ENV['TOOLSET'] || 'other'")
      File.write(rakefile_path, rakefile)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include("Rakefile must default TOOLSET to #{contract.premake_action}")
    end
  end

  it 'reports every missing repository contract input' do
    with_contract_repository(project_root) do |root, contract|
      FileUtils.rm(File.join(root, '.ruby-version'))
      FileUtils.rm(File.join(root, 'Gemfile.lock'))
      FileUtils.rm(File.join(root, 'Rakefile'))
      FileUtils.rm(File.join(root, '.github/workflows/ruby.yml'))

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to eq(
        [
          '.ruby-version is missing; restore it from the repository',
          'Gemfile.lock is missing; restore it from the repository',
          'Rakefile is missing; restore it from the repository',
          '.github/workflows/ruby.yml is missing; restore it from the repository',
        ]
      )
    end
  end

  it 'attributes invalid YAML to the workflow' do
    with_contract_repository(project_root) do |root, contract|
      File.write(File.join(root, '.github/workflows/ruby.yml'), "jobs: [\n")

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include('.github/workflows/ruby.yml is invalid YAML; fix its syntax')
    end
  end

  it 'attributes an unreadable workflow input' do
    with_contract_repository(project_root) do |root, contract|
      workflow_path = File.join(root, '.github/workflows/ruby.yml')
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(workflow_path).and_raise(Errno::EACCES)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include('.github/workflows/ruby.yml is unreadable; repair its permissions')
    end
  end

  it 'attributes YAML constructs rejected by safe loading' do
    invalid_workflows = [
      <<~YAML,
        shared: &shared
          steps: []
        jobs:
          test: *shared
      YAML
      <<~YAML,
        generated: 2020-01-01
        jobs: {}
      YAML
    ]

    invalid_workflows.each do |workflow|
      with_contract_repository(project_root) do |root, contract|
        File.write(File.join(root, '.github/workflows/ruby.yml'), workflow)

        errors = described_class.new(root: root, contract: contract).errors

        expect(errors).to eq(
          ['.github/workflows/ruby.yml cannot be loaded safely as YAML; remove aliases or unsupported YAML constructs']
        )
      end
    end
  end

  it 'rejects non-mapping workflow roots without raising' do
    ['', "workflow\n", "[]\n"].each do |workflow|
      with_contract_repository(project_root) do |root, contract|
        File.write(File.join(root, '.github/workflows/ruby.yml'), workflow)

        errors = described_class.new(root: root, contract: contract).errors

        expect(errors).to eq(
          ['.github/workflows/ruby.yml has invalid workflow structure: document root must be a mapping']
        )
      end
    end
  end

  it 'rejects missing or wrongly typed jobs without raising' do
    ["name: CI\n", "jobs: workflow\n", "jobs: []\n"].each do |workflow|
      with_contract_repository(project_root) do |root, contract|
        File.write(File.join(root, '.github/workflows/ruby.yml'), workflow)

        errors = described_class.new(root: root, contract: contract).errors

        expect(errors).to eq(
          ['.github/workflows/ruby.yml has invalid workflow structure: jobs must be a mapping']
        )
      end
    end
  end

  it 'rejects downstream workflow shape mismatches without raising' do
    invalid_workflows = [
      ["permissions: []\njobs: {}\n", 'permissions must be a mapping'],
      ["concurrency: []\njobs: {}\n", 'concurrency must be a mapping'],
      ["jobs:\n  1: {}\n", 'job names must be strings'],
      ["jobs:\n  test: workflow\n", 'CI job test must be a mapping'],
      ["jobs:\n  test:\n    env: []\n    steps: []\n", 'CI job test env must be a mapping'],
      ["jobs:\n  test:\n    strategy: []\n    steps: []\n", 'CI job test strategy must be a mapping'],
      ["jobs:\n  test:\n    strategy:\n      matrix: []\n    steps: []\n", 'CI job test strategy matrix must be a mapping'],
      ["jobs:\n  test:\n    steps: workflow\n", 'CI job test steps must be a list of mappings'],
      ["jobs:\n  test:\n    steps:\n      - workflow\n", 'CI job test steps must be a list of mappings'],
      ["jobs:\n  test:\n    steps:\n      - with: []\n", 'CI job test step inputs must be mappings'],
    ]

    invalid_workflows.each do |workflow, detail|
      with_contract_repository(project_root) do |root, contract|
        File.write(File.join(root, '.github/workflows/ruby.yml'), workflow)

        errors = described_class.new(root: root, contract: contract).errors

        expect(errors).to eq([".github/workflows/ruby.yml has invalid workflow structure: #{detail}"])
      end
    end
  end
end
