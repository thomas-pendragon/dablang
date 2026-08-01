require 'spec_helper'

require 'rbconfig'
require 'shellwords'
require 'stringio'
require 'tmpdir'

require_relative '../src/shared/system'

describe 'test harness subprocess timeouts' do
  let(:ruby) { RbConfig.ruby }

  def ruby_command(script, *arguments)
    if OS.windows?
      command = [ruby, '-e', script, *arguments]
      return command.map { |part| "\"#{part.to_s.gsub('"', '\\\"')}\"" }.join(' ')
    end

    [ruby, '-e', script, *arguments].shelljoin
  end

  def process_running?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_until_stopped(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep 0.01 while process_running?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  it 'allows a declared-timeout command to complete before its deadline' do
    result = qsystem(ruby_command("STDOUT.write('completed')"), timeout: 5)

    expect(result).to include(timed_out: false, timeout: 5.0)
    expect(result.fetch(:stdout)).to eq('completed')
    expect(result.fetch(:exit_code)).to be_success
  end

  it 'keeps commands without a declared timeout unchanged' do
    result = qsystem(ruby_command("STDOUT.write('no timeout')"))

    expect(result).to include(timed_out: false, timeout: nil)
    expect(result.fetch(:stdout)).to eq('no timeout')
    expect(result.fetch(:exit_code)).to be_success
  end

  it 'fails a timed-out action with stable diagnostics and restores the test session' do
    output = StringIO.new
    error = StringIO.new
    command = ruby_command("STDOUT.write('started'); STDOUT.flush; sleep 60")

    expect do
      DabTestOutput.with_test('test/vm/timeout.vmt', output: output, error: error) do
        DabTestOutput.with_action('VM') { qsystem(command, timeout: 0.25) }
      end
    end.to raise_error(SystemCommandError, /Command timed out after 0.25 seconds/)

    expect(error.string).to include(
      'Dab test failure: test/vm/timeout.vmt',
      'stage: VM',
      "command: #{command}",
      'timeout: 0.25 seconds',
      'outcome: timed out',
      'exit status: 124',
      'started'
    )
    expect(DabTestOutput.current).to be_nil
  end

  it 'terminates a timed-out Unix process group and its child process' do
    skip 'process groups are terminated through taskkill on Windows' if OS.windows?

    Dir.mktmpdir('dab-timeout-child') do |directory|
      child_pid_file = File.join(directory, 'child.pid')
      script = <<~RUBY
        # Keep startup slower than the execution timeout to make the handshake
        # necessary instead of relying on the runner scheduling the child.
        sleep 0.35
        child = Process.spawn(#{ruby.dump}, '-e', 'sleep 60')
        File.write(ARGV.fetch(0), child.to_s)
        STDOUT.write('child-ready')
        STDOUT.flush
        sleep 60
      RUBY

      expect do
        qsystem(
          ruby_command(script, child_pid_file),
          timeout: 0.25,
          ready_output: 'child-ready',
          startup_timeout: 2
        )
      end.to raise_error(SystemCommandError, /Command timed out/)

      child_pid = Integer(File.read(child_pid_file))
      wait_until_stopped(child_pid)
      expect(process_running?(child_pid)).to be(false)
    end
  end
end
