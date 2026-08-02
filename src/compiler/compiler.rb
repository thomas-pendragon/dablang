if ARGV.include?('--version')
  require_relative '../shared/version'
  DabVersion.print_and_exit('compiler')
end

require_relative '../shared/syntax_profile'
require_relative 'syntax_options'
require_relative 'modern_syntax_diagnostics'

begin
  syntax_profile, arguments, syntax_profile_explicit = DabCompilerSyntaxOptions.parse(ARGV)
rescue DabCompilerSyntaxOptionError => e
  warn "compiler: #{e.message}"
  exit 2
end

require_relative '../shared/args_noautorun'

begin
  settings = read_args!(arguments)
  source_units = DabCompilerSyntaxOptions.resolve_inputs(
    syntax_profile: syntax_profile,
    explicit: syntax_profile_explicit,
    inputs: settings[:inputs]
  )
  DabModernSyntaxDiagnostics.validate_source_units!(source_units, ring_bases: settings[:ring_base])
rescue DabCompilerSyntaxOptionError => e
  warn "compiler: #{e.message}"
  exit 2
rescue DabModernSyntaxDiagnosticError => e
  warn "compiler: #{e.diagnostic}"
  exit 2
end

require_relative 'compiler_noautorun'

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

run_dab_compiler(settings, CompilerContext.new, source_units: source_units)
