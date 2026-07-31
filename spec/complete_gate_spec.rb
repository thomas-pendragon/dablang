require 'spec_helper'

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

require_relative '../lib/dab/complete_gate'

module CompleteGateSpecSupport
  class FakeExecutor
    attr_reader :commands

    def initialize(results, &before_call)
      @results = results
      @before_call = before_call
      @commands = []
    end

    def call(command, chdir:)
      commands << [command, chdir]
      @before_call&.call(command, chdir)
      @results.shift
    end
  end

  class FakeGeneratedDocumentation
    def initialize(*snapshots)
      @snapshots = snapshots
    end

    def changed_paths
      @snapshots.empty? ? [] : @snapshots.shift
    end
  end
end

describe Dab::CompleteGate::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }
  let(:generated_documentation) { CompleteGateSpecSupport::FakeGeneratedDocumentation.new }

  def command_result(success, exit_code)
    Dab::CompleteGate::CommandResult.new(success, exit_code)
  end

  it 'runs the preflight, inherited gate, and Ruby RSpec suite exactly once in order' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([
                                                           command_result(true, 0),
                                                           command_result(true, 0),
                                                           command_result(true, 0),
                                                         ])

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(0)
    expect(executor.commands).to eq(
      [
        [%w[ruby script/toolchain_preflight.rb], root],
        [%w[bundle exec rake], root],
        [%w[bundle exec rspec], root],
      ]
    )
    expect(output.string).to eq(
      "complete validation gate: supported toolchain preflight\n" \
      "complete validation gate: inherited build, test, and documentation gate\n" \
      "complete validation gate: Ruby RSpec suite\n" \
      "complete validation gate: PASSED\n"
    )
    expect(error.string).to eq('')
  end

  it 'fails fast and returns the preflight exit status without running the inherited gate' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([command_result(false, 17)])

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(17)
    expect(executor.commands).to eq([[%w[ruby script/toolchain_preflight.rb], root]])
    expect(error.string).to include('FAILED during supported toolchain preflight (ruby script/toolchain_preflight.rb)')
  end

  it 'returns the inherited gate exit status after a successful preflight without running RSpec' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([
                                                           command_result(true, 0),
                                                           command_result(false, 9),
                                                         ])

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(9)
    expect(executor.commands.last.first).to eq(%w[bundle exec rake])
    expect(error.string).to include('FAILED during inherited build, test, and documentation gate (bundle exec rake)')
  end

  it 'returns the Ruby RSpec suite exit status after the inherited gate succeeds' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([
                                                           command_result(true, 0),
                                                           command_result(true, 0),
                                                           command_result(false, 23),
                                                         ])

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(23)
    expect(executor.commands.map(&:first)).to eq(
      [
        %w[ruby script/toolchain_preflight.rb],
        %w[bundle exec rake],
        %w[bundle exec rspec],
      ]
    )
    expect(error.string).to include('FAILED during Ruby RSpec suite (bundle exec rspec)')
  end

  it 'fails before validation and names a pre-existing dirty generated-documentation path' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([])
    generated_documentation = CompleteGateSpecSupport::FakeGeneratedDocumentation.new(
      ['docs\\classes\\array.md']
    )

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(1)
    expect(executor.commands).to be_empty
    expect(error.string).to include('FAILED before supported toolchain preflight')
    expect(error.string).to include("  docs/classes/array.md\n")
  end

  it 'reports every changed generated-documentation path deterministically and skips later stages' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([
                                                           command_result(true, 0),
                                                           command_result(true, 0),
                                                         ])
    generated_documentation = CompleteGateSpecSupport::FakeGeneratedDocumentation.new(
      [],
      [],
      ['docs/vm/opcodes.md', 'docs\\classes\\array.md']
    )

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(1)
    expect(executor.commands.map(&:first)).to eq(
      [
        %w[ruby script/toolchain_preflight.rb],
        %w[bundle exec rake],
      ]
    )
    expect(error.string).to include(
      'FAILED after successful inherited build, test, and documentation gate'
    )
    expect(error.string).to include("  docs/classes/array.md\n  docs/vm/opcodes.md\n")
  end

  it 'preserves an earlier stage exit status while reporting generated-documentation changes' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([command_result(false, 17)])
    generated_documentation = CompleteGateSpecSupport::FakeGeneratedDocumentation.new(
      [],
      ['docs/vm/opcodes.md']
    )

    status = described_class.new(
      root: root,
      executor: executor,
      generated_documentation: generated_documentation,
      output: output,
      error: error
    ).run

    expect(status).to eq(17)
    expect(error.string).to include('FAILED during supported toolchain preflight')
    expect(error.string).to include(
      'tracked generated documentation also changed during failed supported toolchain preflight'
    )
    expect(error.string).to include("  docs/vm/opcodes.md\n")
  end
end

describe Dab::CompleteGate::GeneratedDocumentation do
  def run_git(*arguments)
    _output, error, status = Open3.capture3('git', *arguments, chdir: repository)
    raise error unless status.success?
  end

  def write(relative_path, content)
    path = File.join(repository, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
  end

  around do |example|
    Dir.mktmpdir('dab-generated-documentation-spec') do |directory|
      @repository = directory
      run_git('init', '--quiet')
      run_git('config', 'user.name', 'Dab Test')
      run_git('config', 'user.email', 'dab-test@example.invalid')
      write('docs/vm/opcodes.md', "opcodes\n")
      write('docs/classes.md', "classes\n")
      write('docs/classes/array.md', "array\n")
      write('README.md', "readme\n")
      run_git('add', '.')
      run_git('commit', '--quiet', '-m', 'Add fixtures')
      example.run
    end
  end

  let(:repository) { @repository }

  it 'reports actual tracked generated-documentation mutations as sorted repository paths' do
    write('docs/vm/opcodes.md', "changed opcodes\n")
    write('docs/classes/array.md', "changed array\n")

    expect(described_class.new(root: repository).changed_paths).to eq(
      [
        'docs/classes/array.md',
        'docs/vm/opcodes.md',
      ]
    )
  end

  it 'ignores unrelated tracked changes and untracked build artifacts' do
    write('README.md', "changed readme\n")
    write('build/output.bin', "untracked build output\n")

    expect(described_class.new(root: repository).changed_paths).to be_empty
  end

  it 'reports a closed inspection failure when Git cannot be executed' do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'git')

    expect { described_class.new(root: repository).changed_paths }
      .to raise_error(
        Dab::CompleteGate::GeneratedDocumentationInspectionError,
        /git diff could not be executed:.*git/
      )
  end

  it 'reports a nonzero exit code when Git terminates via signal' do
    status = instance_double(
      Process::Status,
      success?: false,
      exitstatus: nil,
      signaled?: true,
      termsig: 9
    )
    allow(Open3).to receive(:capture3).and_return(['', 'terminated', status])

    expect { described_class.new(root: repository).changed_paths }
      .to raise_error(
        Dab::CompleteGate::GeneratedDocumentationInspectionError,
        'git diff failed with exit status 137: terminated'
      )
  end
end

describe Dab::CompleteGate::SystemExecutor do
  let(:root) { File.expand_path('..', __dir__) }

  it 'returns a nonzero status when a command cannot be executed' do
    result = described_class.new.call(['dab-command-that-does-not-exist'], chdir: root)

    expect(result).not_to be_success
    expect(result.exit_code).to be > 0
  end

  it 'returns a nonzero status for a terminated command on every supported platform' do
    result = described_class.new.call(
      [RbConfig.ruby, '-e', 'Process.kill("TERM", Process.pid)'],
      chdir: root
    )

    expect(result).not_to be_success
    if Gem.win_platform?
      expect(result.exit_code).to be > 0
    else
      expect(result.exit_code).to eq(143)
    end
  end
end

describe 'complete validation gate contract' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'keeps the documented command, CI entrypoint, Rake tasks, and complete-gate stages consistent' do
    documentation = File.read(File.join(root, 'docs/complete-validation.md'))
    workflow = File.read(File.join(root, '.github/workflows/ruby.yml'))

    expect(documentation).to include("```shell\nruby script/complete_gate.rb\n```")
    expect(workflow.scan('run: ruby script/complete_gate.rb').count).to eq(3)
    expect(Dab::CompleteGate::Runner::PREFLIGHT_COMMAND).to eq(%w[ruby script/toolchain_preflight.rb])
    expect(Dab::CompleteGate::Runner::INHERITED_GATE_COMMAND).to eq(%w[bundle exec rake])
    expect(Dab::CompleteGate::Runner::RSPEC_COMMAND).to eq(%w[bundle exec rspec])
    expect(Dab::CompleteGate::GeneratedDocumentation::TRACKED_PATHS).to eq(
      [
        'docs/vm/opcodes.md',
        'docs/classes.md',
        'docs/classes',
      ]
    )
    expect(Dab::CompleteGate::Runner::STAGES.map(&:last)).to eq(
      [
        %w[ruby script/toolchain_preflight.rb],
        %w[bundle exec rake],
        %w[bundle exec rspec],
      ]
    )
    rakefile = File.read(File.join(root, 'Rakefile'))
    expect(rakefile).to include('task dab_fixture_spec: :dab')
    expect(rakefile).to match(/task\s+:spec\s+do\s+psystem\(['\"]bundle exec rspec['\"]\)\s+end/)
    expect(rakefile).to include(':dab_fixture_spec, :format_spec')
  end
end
