require_relative '_requires.rb'

file = STDIN
if $settings[:input]
  file = File.open($settings[:input], 'rb')
end

stream = DabProgramStream.new(file.read)
compiler = DabCompiler.new(stream)
program = compiler.program

program.dump

pp1 = [
  DabPPConvertArgToLocalvar,
  DabPPLower,
  DabPPFixLocalvars,
  DabPPCheckFunctions,
  DabPPCheckSetvarTypes,
  DabPPCheckCallArgsTypes,
]

postprocess = [
  DabPPFixLiterals,
  DabPPReuseConstants,
  DabPPCompactConstants,
  DabPPStripSingleVars,
  DabPPSimplifyConstantProperties,
]

pp1.each do |klass|
  next if program.has_errors?
  STDERR.puts "Will run postprocess <#{klass}>"
  klass.new.run(program)
  program.dump
end

2.times do
  postprocess.each do |klass|
    next if program.has_errors?
    STDERR.puts "Will run postprocess <#{klass}>"
    klass.new.run(program)
    program.dump
  end
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
