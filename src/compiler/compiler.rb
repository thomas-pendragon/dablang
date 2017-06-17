require_relative '../../setup.rb'
require_relative '_requires.rb'
$debug = $settings[:debug]
errap $settings if $debug
$with_cov = $settings[:with_cov]
$opt = true
$opt = false if $settings[:no_opt]
$strip = !!$settings[:strip]
$entry = $settings[:entry]
$no_constants = $settings[:no_constants]
$no_autorelease = $settings[:no_autorelease]

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
  if new_program.has_errors?
    program = new_program
    break
  end
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

program.init!

debug_check!(program, 'rawinit')

while true
  if $debug
    program.dump
    err ''
    err '--~'.yellow * 50
    err ''
  end
  break if program.run_check_callbacks!
  break if program.has_errors?
  next if program.run_processors!([$opt ? :optimize_callbacks : nil].compact)
  next if program.run_processors!([:lower_callbacks])
  next if program.run_processors!([$strip ? :strip_callbacks : nil].compact)
  next if program.run_processors!([:flatten_callbacks])
  break
end

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
