class SystemCommandError < RuntimeError
  attr_accessor :stderr
  attr_accessor :stdout
  def initialize(message, stderr)
    super(message)
    @stderr = stderr
  end
end

def psystem(cmd, capture_stderr = false)
  STDERR.puts " > #{cmd.yellow}"
  tempfile = nil
  if capture_stderr
    tempfile = Tempfile.new('stderr')
    cmd += " 2> #{tempfile.path}"
  end
  unless system cmd
    if tempfile
      stderr = open(tempfile.path).read
    end
    raise SystemCommandError.new("Error during executing #{cmd}", stderr)
  end
ensure
  tempfile&.close
  tempfile&.unlink
end

def psystem_noecho(cmd)
  psystem(cmd, true)
end
