require_relative '_requires.rb'
$debug = $settings[:debug]
$with_cov = $settings[:with_cov]

inputs = $settings[:inputs] || [:stdin]

streams = {}
program = nil
inputs.each do |input|
  file = STDIN
  filename = '<input>'
  if input != :stdin
    file = File.open(input, 'rb')
    filename = input
  end
  stream = DabProgramStream.new(file.read, true, filename)
  compiler = DabCompiler.new(stream)
  streams[filename] = stream
  new_program = compiler.program
  if program
    program.merge!(new_program)
  else
    program = new_program
  end
end

if $debug || $settings[:dump] == 'raw'
  program.dump
end
if $settings[:dump] == 'raw'
  exit(0)
end

pp1 = [
  DabPPConvertArgToLocalvar,
  DabPPAddMissingReturns,
  DabPPOptimize,
  DabPPLower,
  DabPPFixLocalvars,
  DabPPCheckFunctions,
  DabPPCheckSetvarTypes,
  DabPPCheckCallArgsTypes,
  DabPPCheckCallArgsCount,
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
    STDERR.puts e.annotated_source(streams[e.source.source_file])
    STDERR.puts sprintf('%s:%d: error E%04d: %s', e.source.source_file, e.source.source_line, e.error_code, e.message)
  end
  exit(1)
else
  output = DabOutput.new
  program.compile(output)
end
