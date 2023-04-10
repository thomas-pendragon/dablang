require_relative './shared_noautorun'

$autorun = true if $autorun.nil?

class StdlibCompiler
  include BaseFrontend

  def run(settings)
    output = settings[:output]
    input = Dir.glob('stdlib/*.dab')

    asm = settings[:output].gsub('.dabcb', '.dabca')

    compile_options = ''
    assemble_options = ''

    compile_dab_to_asm(input, asm, compile_options)
    assemble(asm, output, assemble_options)
  end
end

if $autorun
  read_args!

  test = StdlibCompiler.new
  test.run_test($settings)
end
