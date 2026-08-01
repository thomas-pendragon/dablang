require_relative 'test_output'

class SystemCommandError < RuntimeError
  attr_accessor :stderr
  attr_accessor :stdout
  attr_accessor :exit_code
  attr_accessor :timeout

  def initialize(message, stderr)
    super(message)
    @stderr = stderr
  end
end

class SystemRunCommand
  attr_reader :command

  def initialize(command)
    @command = command
  end

  def errored?
    @exit_code && @exit_code != 0
  end

  def open_process!(input: nil, input_file: nil, binmode: false)
    @binmode = binmode
    raise 'cannot have both input and input_file' if input && input_file

    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*popen_arguments)
    if input_file
      input = if binmode
                File.binread(input_file)
              else
                File.read(input_file)
              end
    end
    @stdin.binmode if binmode
    raise "expected binmode=#{binmode}, got #{@stdin.binmode?}" unless binmode == @stdin.binmode?

    if input
      len = @stdin.write(input)
      raise 'mismatch' unless len == input.length
    end
    @stdin.close
  end

  def streams
    [@stdout, @stderr]
  end

  def try_update(fd)
    return unless streams.include?(fd)

    data = fd.read_nonblock(1024)
    yield(data, fd == @stderr) unless data.empty?
  rescue IO::WaitReadable
    nil
  rescue EOFError
    fd.close
    nil
  end

  def finished?
    return false unless @wait_thr

    ret = !@wait_thr.alive?
    if ret && !@exit_code
      @exit_code = @wait_thr.value
    end
    ret
  end

  def exit_code
    @exit_code
  end

  def wait_for_exit(seconds = nil)
    return true unless @wait_thr.alive?

    result = seconds.nil? ? @wait_thr.join : @wait_thr.join(seconds)
    @exit_code = @wait_thr.value if result && !@exit_code
    result
  end

  def terminate!
    close_stdin
    if windows?
      terminate_windows_process_tree
    else
      terminate_unix_process_group
    end
    @exit_code = @wait_thr.value unless @wait_thr.alive?
  end

private

  def popen_arguments
    return [@command] if windows?

    [@command, {pgroup: true}]
  end

  def windows?
    OS.windows?
  end

  def close_stdin
    @stdin.close unless @stdin.closed?
  rescue IOError
    nil
  end

  def terminate_unix_process_group
    signal_process_group('TERM')
    wait_for_process_group(1)
    signal_process_group('KILL') if process_group_alive?
    wait_for_exit
  end

  def process_group_alive?
    Process.kill(0, -@wait_thr.pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_for_process_group(seconds)
    deadline = monotonic_time + seconds
    sleep 0.01 while process_group_alive? && monotonic_time < deadline
  end

  def terminate_windows_process_tree
    taskkill('/T')
    return if wait_for_exit(1)

    taskkill('/T', '/F')
    wait_for_exit
  end

  def signal_process_group(signal)
    Process.kill(signal, -@wait_thr.pid)
  rescue Errno::ESRCH
    nil
  end

  def taskkill(*arguments)
    system('taskkill', '/PID', @wait_thr.pid.to_s, *arguments, out: File::NULL, err: File::NULL)
  rescue Errno::ENOENT
    Process.kill('KILL', @wait_thr.pid)
  rescue Errno::ESRCH
    nil
  end
end

def system_with_progress(cmd, input: nil, input_file: nil, show_stderr: true, show_stdout: true, binmode: false,
                         timeout: nil, ready_output: nil, startup_timeout: nil)
  command = SystemRunCommand.new(cmd)
  command.open_process!(input: input, input_file: input_file, binmode: binmode)
  fdlist = command.streams
  stdout = ''
  stderr = ''
  timeout = Float(timeout) if timeout
  if ready_output
    raise ArgumentError.new('startup_timeout is required with ready_output') unless startup_timeout

    startup_timeout = Float(startup_timeout)
  end
  ready = ready_output.nil?
  timeout_limit = ready ? timeout : startup_timeout
  deadline = monotonic_time + timeout_limit if timeout_limit
  timed_out = false
  while true
    fdlist.reject!(&:closed?)
    break if fdlist.empty? && command.finished?

    if deadline && monotonic_time >= deadline && !command.finished?
      command.terminate!
      timed_out = true
      timeout = timeout_limit
      deadline = nil
      next
    end

    if fdlist.empty?
      command.wait_for_exit(deadline && [deadline - monotonic_time, 0].max)
      next
    end

    wait_time = deadline && [deadline - monotonic_time, 0].max
    selected = IO.select(fdlist, nil, nil, wait_time)
    next unless selected

    ready = selected[0]
    data = false
    ready.each do |fd|
      command.try_update(fd) do |line, is_stderr|
        if is_stderr
          DabTestOutput.emit(line, stream: :stderr, display: :stderr) if show_stderr
          stderr += line
        else
          DabTestOutput.emit(line, stream: :stdout, display: :stderr) if show_stdout
          stdout += line
        end
        if !ready && stdout.include?(ready_output)
          ready = true
          timeout_limit = timeout
          deadline = monotonic_time + timeout if timeout
        end
        data = true
      end
    end
    next if data
    break if command.finished?
  end
  {
    exit_code: timed_out ? 124 : command.exit_code,
    stdout: stdout,
    stderr: stderr,
    timed_out: timed_out,
    timeout: timeout,
  }
end

def monotonic_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def psystem_ignore(cmd)
  warn " > #{cmd.yellow}"
  system(cmd)
end

def psystem(cmd)
  warn " > #{cmd.yellow}"
  unless system cmd
    raise SystemCommandError.new("Error during executing #{cmd}", nil)
  end
end

def qsystem(cmd, input: nil, input_file: nil, output_file: nil, timeout: nil, error_file: nil, binmode: false,
            ready_output: nil, startup_timeout: nil)
  DabTestOutput.emit(' >> '.yellow)
  DabTestOutput.emit("timeout #{timeout} ".white) if timeout
  DabTestOutput.emit(cmd.yellow)
  DabTestOutput.emit(" < #{input_file}".white) if input_file
  DabTestOutput.emit(" > #{output_file}".white) if output_file
  DabTestOutput.emit("\n")
  ret = system_with_progress(
    cmd,
    input: input,
    input_file: input_file,
    show_stdout: !output_file,
    show_stderr: !error_file,
    binmode: binmode,
    timeout: timeout,
    ready_output: ready_output,
    startup_timeout: startup_timeout
  )
  DabTestOutput.record_command(
    cmd,
    exit_code: ret[:exit_code],
    stdout: ret[:stdout],
    stderr: ret[:stderr],
    timeout: ret[:timeout],
    timed_out: ret[:timed_out]
  )
  unless ret[:exit_code] == 0
    DabTestOutput.emit("#{ret[:stderr].to_s.red}\n") unless DabTestOutput.current
    message = if ret[:timed_out]
                "Command timed out after #{ret[:timeout]} seconds: #{cmd}"
              else
                "Error during executing #{cmd}"
              end
    error = SystemCommandError.new(message, ret[:stderr])
    error.stdout = ret[:stdout]
    error.timeout = ret[:timeout] if ret[:timed_out]
    status = ret[:exit_code]
    error.exit_code = if status.respond_to?(:exitstatus)
                        status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
                      else
                        status
                      end
    raise error
  end
  File.open(output_file, 'wb') { |file| file << ret[:stdout] } if output_file
  File.open(error_file, 'wb') { |file| file << ret[:stderr] } if error_file
  ret
end
