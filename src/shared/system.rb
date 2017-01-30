require 'colorize'

class SystemCommandError < RuntimeError
end

def psystem(cmd)
  puts " > #{cmd.yellow}"
  unless system cmd
    raise SystemCommandError.new("Error during executing #{cmd}")
  end
end

def psystem_noecho(cmd)
  cmd_noecho = "#{cmd} 2>/dev/null"
  begin
    psystem cmd_noecho
  rescue SystemCommandError
    psystem cmd
  end
end
