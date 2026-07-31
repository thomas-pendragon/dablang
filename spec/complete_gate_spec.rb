require 'spec_helper'

require 'stringio'
require 'rbconfig'

require_relative '../lib/dab/complete_gate'

module CompleteGateSpecSupport
  class FakeExecutor
    attr_reader :commands

    def initialize(results)
      @results = results
      @commands = []
    end

    def call(command, chdir:)
      commands << [command, chdir]
      @results.shift
    end
  end
end

describe Dab::CompleteGate::Runner do
  let(:root) { File.expand_path('..', __dir__) }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  def command_result(success, exit_code)
    Dab::CompleteGate::CommandResult.new(success, exit_code)
  end

  it 'runs the supported-toolchain preflight before the complete inherited gate' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([
                                                           command_result(true, 0),
                                                           command_result(true, 0),
                                                         ])

    status = described_class.new(root: root, executor: executor, output: output, error: error).run

    expect(status).to eq(0)
    expect(executor.commands).to eq(
      [
        [%w[ruby script/toolchain_preflight.rb], root],
        [%w[bundle exec rake], root],
      ]
    )
    expect(output.string).to eq(
      "complete validation gate: supported toolchain preflight\n" \
      "complete validation gate: inherited build, test, and documentation gate\n" \
      "complete validation gate: PASSED\n"
    )
    expect(error.string).to eq('')
  end

  it 'fails fast and returns the preflight exit status without running the inherited gate' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([command_result(false, 17)])

    status = described_class.new(root: root, executor: executor, output: output, error: error).run

    expect(status).to eq(17)
    expect(executor.commands).to eq([[%w[ruby script/toolchain_preflight.rb], root]])
    expect(error.string).to include('FAILED during supported toolchain preflight (ruby script/toolchain_preflight.rb)')
  end

  it 'returns the inherited gate exit status after a successful preflight' do
    executor = CompleteGateSpecSupport::FakeExecutor.new([
                                                           command_result(true, 0),
                                                           command_result(false, 9),
                                                         ])

    status = described_class.new(root: root, executor: executor, output: output, error: error).run

    expect(status).to eq(9)
    expect(executor.commands.last.first).to eq(%w[bundle exec rake])
    expect(error.string).to include('FAILED during inherited build, test, and documentation gate (bundle exec rake)')
  end
end

describe Dab::CompleteGate::SystemExecutor do
  let(:root) { File.expand_path('..', __dir__) }

  it 'returns a nonzero status when a command cannot be executed' do
    result = described_class.new.call(['dab-command-that-does-not-exist'], chdir: root)

    expect(result).not_to be_success
    expect(result.exit_code).to be > 0
  end

  it 'maps a signal-terminated command to its conventional exit status' do
    result = described_class.new.call(
      [RbConfig.ruby, '-e', 'Process.kill("TERM", Process.pid)'],
      chdir: root
    )

    expect(result).not_to be_success
    expect(result.exit_code).to eq(143)
  end
end

describe 'complete validation gate contract' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'keeps the documented command, CI entrypoint, and inherited gate consistent' do
    documentation = File.read(File.join(root, 'docs/complete-validation.md'))
    workflow = File.read(File.join(root, '.github/workflows/ruby.yml'))

    expect(documentation).to include("```shell\nruby script/complete_gate.rb\n```")
    expect(workflow.scan('run: ruby script/complete_gate.rb').count).to eq(3)
    expect(Dab::CompleteGate::Runner::PREFLIGHT_COMMAND).to eq(%w[ruby script/toolchain_preflight.rb])
    expect(Dab::CompleteGate::Runner::INHERITED_GATE_COMMAND).to eq(%w[bundle exec rake])
    expect(File.read(File.join(root, 'Rakefile'))).to include('task spec: :dab')
  end
end
