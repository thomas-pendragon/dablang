require_relative '_requires.rb'

stream = DabProgramStream.new(STDIN.read)
compiler = DabCompiler.new(stream)
program = compiler.program

program.dump

postprocess = [
  DabPPLower,
  DabPPFixLiterals,
  DabPPFixLocalvars,
  DabPPReuseConstants,
  DabPPCompactConstants,
  DabPPCheckFunctions,
  DabPPCheckSetvarTypes,
  DabPPCheckCallArgsTypes,
  DabPPStripSingleVars,
  DabPPSimplifyConstantProperties,
]

2.times do
  postprocess.each do |klass|
    STDERR.puts "Will run postprocess <#{klass}>"
    klass.new.run(program)
    program.dump
  end
  break if program.has_errors?
end

STDERR.puts "\n--\n\n"

program.dump

if program.has_errors?
  program.errors.each do |e|
    STDERR.puts sprintf('%s:%d: error E%04d: %s', e.source.source_file, e.source.source_line, e.error_code, e.message)
  end
  exit(1)
else
  output = DabOutput.new
  program.compile(output)
end
