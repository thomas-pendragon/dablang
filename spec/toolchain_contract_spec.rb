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

  it 'keeps the manifest, Ruby default, lockfile, and all five CI jobs consistent' do
    with_contract_repository(project_root) do |root, contract|
      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to be_empty
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
      workflow = workflow.sub(
        "      - name: Check supported toolchain\n        run: ruby script/toolchain_preflight.rb\n      - name: Run tests",
        "      - name: Run tests\n        run: bundle exec rake\n      - name: Check supported toolchain"
      )
      File.write(workflow_path, workflow)

      errors = described_class.new(root: root, contract: contract).errors

      expect(errors).to include('CI job test Ruby matrix must match the supported-toolchain manifest')
      expect(errors).to include('CI job test must install Premake 5.0.0-beta8 from premake-5.0.0-beta8-linux.tar.gz')
      expect(errors).to include('CI job test must run the preflight after Premake installation and before tests')
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
end
