require_relative '_requires.rb'
$debug = $settings[:debug]
errap $settings if $debug
$with_cov = $settings[:with_cov]
$opt = true
$opt = false if $settings[:no_opt]

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

def debug_check!(program, type)
  if $debug || $settings[:dump] == type
    program.dump
  end
  if $settings[:dump] == type
    exit(0)
  end
end

debug_check!(program, 'raw')

program.run_processors!(:init_callbacks)

debug_check!(program, 'rawinit')

def run_postprocess!(program, list)
  list.each do |klass|
    next if program.has_errors?
    STDERR.puts "Will run postprocess <#{klass}>" if $debug
    klass.new.run(program)
    program.dump if $debug
  end
end

pp0 = [
  DabPPBlockify,
  DabPPBlockReorder,
]

run_postprocess!(program, pp0)

debug_check!(program, 'blockify')

pp11 = [
  DabPPConvertArgToLocalvar,
  DabPPAddMissingReturns,
  ($opt ? DabPPOptimize : nil),
].compact

run_postprocess!(program, pp11)
debug_check!(program, 'middle1')

while true
  break if program.run_check_callbacks!
  break if program.has_errors?
  break unless program.run_processors!([:lower_callbacks, $opt ? :optimize_callbacks : nil].compact)
end

debug_check!(program, 'processors')

postprocess = [
  DabPPFixLiterals,
  DabPPReuseConstants,
  DabPPCompactConstants,
  DabPPStripSingleVars,
  DabPPSimplifyConstantProperties,
]

2.times do
  run_postprocess!(program, postprocess)
end

STDERR.puts "\n--\n\n" if $debug

debug_check!(program, 'post')

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
