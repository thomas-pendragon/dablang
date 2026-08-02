if ARGV.include?('--version')
  require_relative '../shared/version'
  DabVersion.print_and_exit('compiler')
end

require_relative '../shared/syntax_profile'
require_relative 'syntax_options'

begin
  syntax_profile, arguments, syntax_profile_explicit = DabCompilerSyntaxOptions.parse(ARGV)
rescue DabCompilerSyntaxOptionError => e
  warn "compiler: #{e.message}"
  exit 2
end

require_relative 'compiler_noautorun'

settings = read_args!(arguments)
syntax_profile = DabCompilerSyntaxOptions.resolve(
  syntax_profile: syntax_profile,
  explicit: syntax_profile_explicit,
  inputs: settings[:inputs]
)

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

run_dab_compiler(settings, CompilerContext.new, syntax_profile: syntax_profile)
