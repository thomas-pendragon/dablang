require_relative '_requires.rb'
$debug = $settings[:debug]

file = STDIN
if $settings[:input]
  file = File.open($settings[:input], 'rb')
end

stream = DabProgramStream.new(file.read)
compiler = DabCompiler.new(stream)
program = compiler.program

if $debug || $settings[:dump] == 'raw'
  program.dump
end
if $settings[:dump] == 'raw'
  exit(0)
end

pp1 = [
  DabPPConvertArgToLocalvar,
  DabPPAddMissingReturns,
  DabPPLower,
  DabPPFixLocalvars,
  DabPPCheckFunctions,
  DabPPCheckSetvarTypes,
  DabPPCheckCallArgsTypes,
]

pp1.each do |klass|
  next if program.has_errors?
  STDERR.puts "Will run postprocess <#{klass}>" if $debug
  klass.new.run(program)
  program.dump if $debug
end

if $debug || $settings[:dump] == 'middle'
  program.dump
end
if $settings[:dump] == 'middle'
  exit(0)
end

postprocess = [
  DabPPFixLiterals,
  DabPPReuseConstants,
  DabPPCompactConstants,
  DabPPStripSingleVars,
  DabPPSimplifyConstantProperties,
]

2.times do
  postprocess.each do |klass|
    next if program.has_errors?
    STDERR.puts "Will run postprocess <#{klass}>" if $debug
    klass.new.run(program)
    program.dump if $debug
  end
end

STDERR.puts "\n--\n\n" if $debug

if $debug || $settings[:dump] == 'post'
  program.dump
end
if $settings[:dump] == 'post'
  exit(0)
end

if program.has_errors?
  program.errors.each do |e|
    STDERR.puts e.annotated_source(stream)
    STDERR.puts sprintf('%s:%d: error E%04d: %s', e.source.source_file, e.source.source_line, e.error_code, e.message)
  end
  exit(1)
else
  output = DabOutput.new
  program.compile(output)
end
