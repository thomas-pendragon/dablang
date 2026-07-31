require 'spec_helper'

require 'json'
require 'open3'
require 'tmpdir'

require_relative '../lib/dab/test_suite_manifest'

describe Dab::TestSuiteManifest::Validator do
  let(:root) { File.expand_path('..', __dir__) }
  let(:manifest_path) { File.join(root, 'config/test_suites.json') }
  let(:validator) { described_class.new(root: root) }

  def manifest
    JSON.parse(File.binread(manifest_path))
  end

  def validate_document(document)
    Dir.mktmpdir('dab-test-suite-manifest') do |directory|
      path = File.join(directory, 'manifest.json')
      File.binwrite(path, JSON.pretty_generate(document))
      return validator.validate(path: path)
    end
  end

  def suite(document, id)
    document.fetch('suites').find { |entry| entry.fetch('id') == id }
  end

  it 'validates the committed manifest against the current Rake and complete-gate topology' do
    result = validator.validate(path: manifest_path)

    expect(result).to be_success
    expect(result.errors).to be_empty
  end

  it 'represents every discovered Rake suite and the standalone RSpec suite exactly once' do
    document = manifest
    topology = Dab::TestSuiteManifest::Topology.new(root: root)
    rake_tasks = document.fetch('suites').filter_map do |entry|
      topology.fixture_task_for(entry['rake_task']) if entry['kind'] == 'rake'
    end
    command_suites = document.fetch('suites').select { |entry| entry['kind'] == 'command' }

    expect(rake_tasks).to contain_exactly(*topology.fixture_tasks)
    expect(rake_tasks.uniq).to eq(rake_tasks)
    expect(command_suites.map { |entry| entry['command'] }).to eq(topology.suite_commands)
  end

  it 'represents the direct legacy source-to-VM smoke once and wires all of its contract inputs' do
    document = manifest
    topology = Dab::TestSuiteManifest::Topology.new(root: root)
    smoke_entries = document.fetch('suites').select do |entry|
      entry['rake_task'] == 'legacy_source_vm_smoke'
    end

    expect(smoke_entries.length).to eq(1)
    expect(topology.task_prerequisites('default').count('legacy_source_vm_smoke')).to eq(1)
    expect(topology.gate_task?('legacy_source_vm_smoke')).to be(true)
    expect(topology.task_inputs('legacy_source_vm_smoke')).to include(
      'test/legacy_source_vm_smoke/contract.json',
      'test/legacy_source_vm_smoke/program.dab'
    )
  end

  it 'represents the dedicated AddressSanitizer suite exactly once outside the complete gate' do
    document = manifest
    topology = Dab::TestSuiteManifest::Topology.new(root: root)
    entries = document.fetch('suites').select { |entry| entry['rake_task'] == 'address_sanitizer_spec' }

    expect(entries.length).to eq(1)
    expect(entries.first.fetch('state')).to eq('active')
    expect(entries.first.fetch('in_complete_gate')).to be(false)
    expect(topology.gate_task?('address_sanitizer_spec')).to be(false)
    expect(topology.task_inputs('address_sanitizer_spec')).to include(
      'test/address_sanitizer/heap_buffer_overflow.cpp',
      'test/address_sanitizer/legacy_smoke_leak_contract.json'
    )
  end

  it 'fails closed for malformed JSON' do
    Dir.mktmpdir('dab-test-suite-manifest') do |directory|
      path = File.join(directory, 'manifest.json')
      File.binwrite(path, '{')

      result = validator.validate(path: path)

      expect(result).not_to be_success
      expect(result.errors.join("\n")).to include('manifest is malformed JSON')
    end
  end

  it 'rejects wrong root and container types and unsupported schemas' do
    wrong_root = validate_document([])
    wrong_containers = validate_document('schema_version' => 2, 'suites' => {}, 'exceptions' => {})

    expect(wrong_root.errors).to include('root must be an object, got Array')
    expect(wrong_containers.errors).to include('schema_version must be 1, got 2')
    expect(wrong_containers.errors).to include('suites must be an array, got Hash')
    expect(wrong_containers.errors).to include('exceptions must be an array, got Hash')
  end

  it 'rejects unknown states, duplicate IDs, missing commands, and missing reasons' do
    document = manifest
    document.fetch('suites').first['state'] = 'unknown'
    document.fetch('suites')[1]['id'] = document.fetch('suites').first.fetch('id')
    document.fetch('suites')[2].delete('command')
    suite(document, 'rake-build-examples').delete('reason')
    build_examples_index = document.fetch('suites').index { |entry| entry['id'] == 'rake-build-examples' }

    result = validate_document(document)

    expect(result.errors).to include('suites[0].state must be one of active, pending, disabled')
    expect(result.errors.grep(/duplicate id/)).not_to be_empty
    expect(result.errors).to include('suites[2] is missing fields: command')
    expect(result.errors).to include("suites[#{build_examples_index}].reason must be a non-empty string")
  end

  it 'rejects missing Rake tasks and source paths' do
    missing_task = manifest
    suite(missing_task, 'rake-minitest')['rake_task'] = 'missing_spec'
    suite(missing_task, 'rake-minitest')['command'] = %w[bundle exec rake missing_spec]
    missing_glob = manifest
    suite(missing_glob, 'rspec')['source_glob'] = 'spec/missing/**/*_spec.rb'

    task_result = validate_document(missing_task)
    glob_result = validate_document(missing_glob)

    expect(task_result.errors).to include('suite rake-minitest: Rake task "missing_spec" does not exist')
    expect(glob_result.errors).to include(
      'entry rspec: source_glob matches no files: spec/missing/**/*_spec.rb'
    )
  end

  it 'catches manifest drift from default Rake and complete-gate wiring' do
    rake_drift = manifest
    suite(rake_drift, 'rake-minitest')['in_complete_gate'] = false
    command_drift = manifest
    command_drift.fetch('suites').reject! { |entry| entry['id'] == 'rspec' }

    rake_result = validate_document(rake_drift)
    command_result = validate_document(command_drift)

    expect(rake_result.errors).to include(
      'suite rake-minitest: in_complete_gate is false, but current wiring is true'
    )
    expect(command_result.errors.join("\n")).to include('manifest is missing complete-gate command suites')
    expect(command_result.errors.join("\n")).to include('["bundle", "exec", "rspec"]')
  end

  it 'rejects non-boolean gate-membership declarations' do
    document = manifest
    suite(document, 'rake-minitest')['in_complete_gate'] = 'yes'

    result = validate_document(document)

    expect(result.errors).to include('suites[0].in_complete_gate must be a boolean')
  end

  it 'requires portable paths and reports multiple diagnostics deterministically' do
    document = manifest
    suite(document, 'rake-minitest')['source_glob'] = 'test\\minitest\\*.dab'
    suite(document, 'rake-vm')['in_complete_gate'] = false

    first = validate_document(document)
    second = validate_document(document)

    expect(first.errors).to eq(first.errors.sort)
    expect(second.errors).to eq(first.errors)
    expect(first.errors).to include(
      'source_glob must be a portable repository-relative path: "test\\\\minitest\\\\*.dab"'
    )
  end

  it 'fails when pending or disabled evidence no longer matches repository behavior' do
    pattern_drift = manifest
    pattern_drift.fetch('exceptions').first.fetch('evidence')['value'] = %w[definitely absent marker].join('-')
    excluded_drift = manifest
    excluded = excluded_drift.fetch('exceptions').find { |entry| entry['id'] == 'dab-disabled-leak-fixtures' }
    excluded['source_glob'] = 'test/dab/*.dabt'

    pattern_result = validate_document(pattern_drift)
    excluded_result = validate_document(excluded_drift)

    expect(pattern_result.errors.join("\n")).to include('matches none of its source files')
    expect(excluded_result.errors.join("\n")).to include('files are now wired to dab_fixture_spec')
  end
end

describe 'test suite manifest command' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'validates the committed manifest through the documented read-only command' do
    output, error, status = Open3.capture3(
      'bundle', 'exec', 'ruby', 'script/test_suite_manifest.rb',
      chdir: root
    )

    expect(status).to be_success
    expect(output).to match(/\Atest suite manifest: OK \(\d+ suites, \d+ exceptions\)\n\z/)
    expect(error).to eq('')
  end
end
