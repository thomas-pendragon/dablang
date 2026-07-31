require_relative 'test_output'

class SystemCommandError < RuntimeError
  attr_accessor :stderr
  attr_accessor :stdout
  attr_accessor :exit_code

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

    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)
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

    line = if @binmode
             fd.read(1024)
           else
             fd.gets
           end
    yield(line, fd == @stderr) if line
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
end

def system_with_progress(cmd, input: nil, input_file: nil, show_stderr: true, show_stdout: true, binmode: false)
  command = SystemRunCommand.new(cmd)
  command.open_process!(input: input, input_file: input_file, binmode: binmode)
  fdlist = command.streams
  stdout = ''
  stderr = ''
  while true
    fdlist.reject!(&:closed?)
    break if fdlist.empty?

    ready = IO.select(fdlist)[0]
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
        data = true
      end
    end
    next if data
    break if command.finished?
  end
  {
    exit_code: command.exit_code,
    stdout: stdout,
    stderr: stderr,
  }
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

def qsystem(cmd, input: nil, input_file: nil, output_file: nil, timeout: nil, error_file: nil, binmode: false)
  DabTestOutput.emit(' >> '.yellow)
  DabTestOutput.emit("timeout #{timeout} ".white) if timeout
  DabTestOutput.emit(cmd.yellow)
  DabTestOutput.emit(" < #{input_file}".white) if input_file
  DabTestOutput.emit(" > #{output_file}".white) if output_file
  DabTestOutput.emit("\n")
  ret = system_with_progress(cmd, input: input, input_file: input_file, show_stdout: !output_file, show_stderr: !error_file, binmode: binmode)
  DabTestOutput.record_command(cmd, exit_code: ret[:exit_code], stdout: ret[:stdout], stderr: ret[:stderr])
  unless ret[:exit_code] == 0
    DabTestOutput.emit("#{ret[:stderr].to_s.red}\n") unless DabTestOutput.current
    error = SystemCommandError.new("Error during executing #{cmd}", ret[:stderr])
    error.stdout = ret[:stdout]
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
