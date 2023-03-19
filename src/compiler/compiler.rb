require_relative './compiler_noautorun'

settings = read_args!

class CompilerContext
  def stdin
    STDIN
  end

  def stdout
    STDOUT
  end

  def stderr
    STDERR
  end

  def exit(code)
    Kernel.send(:exit, code)
  end
end

run_dab_compiler(settings, CompilerContext.new)
