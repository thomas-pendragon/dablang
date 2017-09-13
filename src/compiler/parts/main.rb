def debug_check!(settings, program, type)
  if $debug || settings[:dump] == type
    program.dump
  end
  if settings[:dump] == type
    exit(0)
  end
end

def run_dab_compiler(settings, context)
  $dab_benchmark_enabled = settings[:benchmark]
  $dab_benchmark_show_result = settings[:show_benchmark]

  dab_benchmark_start_time = Time.now

  dab_benchmark('compile') do
    $debug = settings[:debug]
    errap settings if $debug
    $with_cov = settings[:with_cov]
    $opt = true
    $opt = false if settings[:no_opt]
    $strip = !!settings[:strip]
    $entry = settings[:entry]
    $no_constants = settings[:no_constants]
    $no_autorelease = settings[:no_autorelease]
    $feature_reflection = settings[:with_reflection]
    $feature_attributes = settings[:with_attributes]

    inputs = settings[:inputs] || [:stdin]

    program = nil
    streams = {}
    dab_benchmark('parse') do
      inputs.each do |input|
        file = context.stdin
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
    end

    debug_check!(settings, program, 'raw')

    dab_benchmark('init') do
      program.init!
    end

    debug_check!(settings, program, 'rawinit')

    dab_benchmark('process') do
      while true
        if $debug
          program.dump
          err ''
          err '--~'.yellow * 50
          err ''
        end
        break if dab_benchmark('dirty_check') do
          program.run_dirty_check_callbacks!
        end
        break if dab_benchmark('check') do
          program.run_check_callbacks!
        end
        break if program.has_errors?
        next if $opt && dab_benchmark('optimize') do
          program.run_optimize_processors!
        end
        next if dab_benchmark('lower') do
          program.run_lower_processors!
        end
        next if dab_benchmark('ssa') do
          program.run_ssa_processors!
        end
        next if $opt && dab_benchmark('optimize-ssa') do
          program.run_optimize_ssa_processors!
        end
        next if dab_benchmark('post-ssa') do
          program.run_post_ssa_processors!
        end
        next if dab_benchmark('late_lower') do
          program.run_late_lower_processors!
        end
        next if $strip && dab_benchmark('strip') do
          program.run_strip_processors!
        end
        next if dab_benchmark('flatten') do
          program.run_flatten_processors!
        end
        break
      end
    end

    debug_check!(settings, program, 'post')

    if program.has_errors?
      program.errors.each do |e|
        context.stderr.puts e.annotated_source(streams[e.source.source_file])
        context.stderr.puts sprintf('%s:%d: error E%04d: %s', e.source.source_file, e.source.source_line || -1, e.error_code, e.message)
      end
      context.exit(1)
    else
      output = DabOutput.new(context)
      program.compile(output)
    end
  end

  dab_benchmark_print!

  if $dab_benchmark_show_result
    time = Time.now - dab_benchmark_start_time
    printf("Total running time: %.2fs\n", time)
  end
end