require 'colorize'

class SystemCommandError < RuntimeError
  attr_accessor :stderr
  def initialize(message, stderr)
    super(message)
    @stderr = stderr
  end
end

def psystem(cmd, capture_stderr = false)
  puts " > #{cmd.yellow}"
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
  cmd_noecho = "#{cmd} 2>/dev/null"
  begin
    psystem cmd_noecho
  rescue SystemCommandError
    psystem(cmd, true)
  end
end
