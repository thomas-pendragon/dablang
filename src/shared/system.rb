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

  def open_process!(input_file = nil)
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)
    if input_file
      text = File.read(input_file)
      len = @stdin.write(text)
      raise 'mismatch' unless len == text.length
    end
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

def system_with_progress(cmd, input_file: nil)
  command = SystemRunCommand.new(cmd)
  command.open_process!(input_file)
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
          stderr += line
        else
          STDERR.print line
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

def qsystem(cmd, input_file: nil, output_file: nil, timeout: nil, error_file: nil)
  STDERR.print ' >> '.yellow
  STDERR.print "timeout #{timeout} ".white if timeout
  STDERR.print cmd.yellow
  STDERR.print " < #{input_file}".white if input_file
  STDERR.print " > #{output_file}".white if output_file
  STDERR.print "\n"
  ret = system_with_progress(cmd, input_file: input_file)
  unless ret[:exit_code] == 0
    STDERR.puts ret[:stderr].to_s.red
    raise SystemCommandError.new("Error during executing #{cmd}", ret[:stderr])
  end
  File.open(output_file, 'wb') { |file| file << ret[:stdout] } if output_file
  File.open(error_file, 'wb') { |file| file << ret[:stderr] } if error_file
  ret
end
