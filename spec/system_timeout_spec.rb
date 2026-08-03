require 'spec_helper'

require 'rbconfig'
require 'shellwords'
require 'stringio'
require 'tmpdir'

require_relative '../src/shared/system'

module SystemTimeoutSpecSupport
  class SequencedRead
    attr_reader :read_count

    def initialize(*outcomes)
      @outcomes = outcomes
      @closed = false
      @read_count = 0
    end

    def read_nonblock(_length)
      @read_count += 1
      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(Exception)
      raise EOFError if outcome == :eof

      outcome
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end
  end

  class FakeRunCommand < SystemRunCommand
    attr_reader :terminate_count

    def initialize(stdout:, stderr:, finished:, exit_code: 0)
      super('ignored')
      @stdout = stdout
      @stderr = stderr
      @finished = finished
      @exit_code = exit_code
      @terminate_count = 0
      @child_alive = !finished
      @wait_thread_alive = !finished
    end

    def open_process!(**)
      nil
    end

    def finished?
      @finished
    end

    def terminate!
      @terminate_count += 1
      streams.each(&:close)
      @finished = true
      @child_alive = false
      @wait_thread_alive = false
    end

    def wait_for_exit(_seconds = nil)
      @finished
    end

    def child_alive?
      @child_alive
    end

    def wait_thread_alive?
      @wait_thread_alive
    end
  end
end

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

  def select_open_streams
    allow(IO).to receive(:select) do |streams, *_arguments|
      [streams.reject(&:closed?), [], []]
    end
  end

  it 'reports data, transient reads, and EOF as distinct update outcomes' do
    stdout = SystemTimeoutSpecSupport::SequencedRead.new('before', Errno::EINTR.new, 'after', :eof)
    stderr = SystemTimeoutSpecSupport::SequencedRead.new(:eof)
    command = SystemTimeoutSpecSupport::FakeRunCommand.new(stdout: stdout, stderr: stderr, finished: true)
    output = ''

    expect(command.try_update(stdout) { |data, _| output += data }).to eq(:data)
    expect(command.try_update(stdout) { |data, _| output += data }).to eq(:repoll)
    expect(command.try_update(stdout) { |data, _| output += data }).to eq(:data)
    expect(command.try_update(stdout) { |data, _| output += data }).to eq(:eof)
    expect(output).to eq('beforeafter')
  end

  it 're-polls after EINTR even when the child has exited, then drains both streams' do
    stdout = SystemTimeoutSpecSupport::SequencedRead.new('before-', Errno::EINTR.new, 'after', :eof)
    stderr = SystemTimeoutSpecSupport::SequencedRead.new('error', :eof)
    command = SystemTimeoutSpecSupport::FakeRunCommand.new(stdout: stdout, stderr: stderr, finished: true)
    select_open_streams
    allow(SystemRunCommand).to receive(:new).and_return(command)

    result = system_with_progress('ignored', show_stdout: false, show_stderr: false)

    expect(result).to include(exit_code: 0, stdout: 'before-after', stderr: 'error', timed_out: false)
    expect(IO).to have_received(:select).exactly(4).times
  end

  it 're-polls after repeated EINTR, preserves the deadline, and terminates once' do
    stdout = SystemTimeoutSpecSupport::SequencedRead.new(Errno::EINTR.new, Errno::EINTR.new)
    stderr = SystemTimeoutSpecSupport::SequencedRead.new(:eof)
    command = SystemTimeoutSpecSupport::FakeRunCommand.new(
      stdout: stdout,
      stderr: stderr,
      finished: false,
      exit_code: 15
    )
    monotonic_times = [0.0, 0.0, 0.0, 0.4, 0.4, 1.0]
    wait_times = []
    allow(self).to receive(:monotonic_time) { monotonic_times.shift }
    allow(IO).to receive(:select) do |streams, _write, _error, wait_time|
      wait_times << wait_time
      [[streams.first], [], []]
    end
    allow(SystemRunCommand).to receive(:new).and_return(command)

    result = system_with_progress('ignored', timeout: 1, show_stdout: false, show_stderr: false)

    expect(result).to include(exit_code: 124, stdout: '', stderr: '', timed_out: true, timeout: 1.0)
    expect(wait_times).to eq([1.0, 0.6])
    expect(command.terminate_count).to eq(1)
    expect(command).to be_finished
    expect(command).not_to be_child_alive
    expect(command).not_to be_wait_thread_alive
    expect(command.streams).to all(be_closed)
    expect(monotonic_times).to be_empty
  end

  it 're-polls IO::WaitReadable through IO.select instead of retrying the read in place' do
    stdout = SystemTimeoutSpecSupport::SequencedRead.new(IO::EAGAINWaitReadable.new, 'completed', :eof)
    stderr = SystemTimeoutSpecSupport::SequencedRead.new(:eof)
    command = SystemTimeoutSpecSupport::FakeRunCommand.new(stdout: stdout, stderr: stderr, finished: true)
    select_open_streams
    allow(SystemRunCommand).to receive(:new).and_return(command)

    result = system_with_progress('ignored', show_stdout: false, show_stderr: false)

    expect(result).to include(exit_code: 0, stdout: 'completed', stderr: '', timed_out: false)
    expect(IO).to have_received(:select).exactly(3).times
    expect(stdout.read_count).to eq(3)
  end

  [Interrupt.new, SignalException.new('TERM'), Errno::EIO.new].each do |failure|
    it "propagates #{failure.class} from subprocess output reads" do
      stdout = SystemTimeoutSpecSupport::SequencedRead.new(failure)
      command = SystemTimeoutSpecSupport::FakeRunCommand.new(
        stdout: stdout,
        stderr: SystemTimeoutSpecSupport::SequencedRead.new(:eof),
        finished: true
      )

      expect { command.try_update(stdout) }.to raise_error(failure.class)
    end
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
      end.to raise_error(SystemCommandError, /Command timed out/) { |error| expect(error.timeout).to eq(0.25) }

      child_pid = Integer(File.read(child_pid_file))
      wait_until_stopped(child_pid)
      expect(process_running?(child_pid)).to be(false)
    end
  end
end
