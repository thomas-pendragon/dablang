class SystemCommandError < RuntimeError
  attr_accessor :stderr
  attr_accessor :stdout
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

  def open_process!
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)
    @stdin.close
  end

  def streams
    [@stdout, @stderr]
  end

  def try_update(fd)
    return unless streams.include?(fd)
    line = fd.gets
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

def system_with_progress(cmd)
  command = SystemRunCommand.new(cmd)
  command.open_process!
  fdlist = command.streams
  stdout = ''
  stderr = ''
  while true
    fdlist.reject!(&:closed?)
    break if fdlist.empty?
    ready = IO.select(fdlist)[0]
    ready.each do |fd|
      command.try_update(fd) do |line, is_stderr|
        print line
        if is_stderr
          stderr += line
        else
          stdout += line
        end
      end
    end
    break if command.finished?
  end
  {
    exit_code: command.exit_code,
    stdout: stdout,
    stderr: stderr,
  }
end

def psystem_ignore(cmd)
  STDERR.puts " > #{cmd.yellow}"
  system(cmd)
end

def psystem_capture(cmd)
  STDERR.puts " > #{cmd.yellow}"
  ret = system_with_progress(cmd)
  unless ret[:exit_code] == 0
    raise SystemCommandError.new("Error during executing #{cmd}", ret[:stderr])
  end
end

def psystem(cmd, capture_stderr = false)
  if capture_stderr
    return psystem_capture(cmd)
  end
  STDERR.puts " > #{cmd.yellow}"
  unless system cmd
    raise SystemCommandError.new("Error during executing #{cmd}", nil)
  end
end

def psystem_noecho(cmd)
  psystem(cmd, true)
end

def psystem_noecho_timeout(cmd, timeout = 10)
  cmd = "timeout #{timeout} #{cmd}"
  psystem_noecho(cmd)
end
