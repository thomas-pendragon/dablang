class DabCompilerFrontend
  attr_reader :source_units, :syntax_profile

  def initialize(syntax_profile: DabSyntaxProfile::LEGACY, source_units: nil)
    @syntax_profile = DabSyntaxProfile.validate(syntax_profile)
    @source_units = source_units&.map { |source_unit| DabSourceUnit.validate(source_unit) }&.freeze
  end

  def debug_check!(settings, program, type)
    if $debug
      err ''
      err '~'.green * 50
      err " > #{type}"
      err ''
    end
    if $debug || settings[:dump] == type
      program.dump
    end
    if settings[:dump] == type
      exit(0)
    end
  end

  def nop; end

  def run(settings, context)
    @source_units ||= source_units_for(settings)
    DabModernSyntaxDiagnostics.validate_source_units!(@source_units)
    @settings = settings

    ring_base = settings[:ring_base]

    program = nil

    symbols = []
    extra_offset = 0

    ring_base&.each do |base|
      new_program, symbols = DabBinReader.new.parse_ring(base, symbols, extra_offset)
      extra_offset = new_program.start_offset

      if program
        program.merge!(new_program)
      else
        program = new_program
      end
    end

    $debug_code_dump = settings[:debug_code_dump]

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
      $entry = settings[:entry] || 'main'
      $no_autorelease = settings[:no_autorelease]
      $multipass = settings[:multipass]

      streams = {}
      dab_benchmark('parse') do
        source_units.each do |source_unit|
          content = source_unit.input == :stdin ? context.stdin.read : File.binread(source_unit.input)
          stream = DabProgramStream.new(content, true, source_unit: source_unit)
          compiler = DabCompiler.new(stream)
          streams[source_unit.filename] = stream
          classes = []
          classes = program.class_names if program
          new_program = compiler.program(classes, parent_unit: program)
          program = new_program

          break if new_program.has_errors?
        end
      end

      debug_check!(settings, program, 'raw0')

      dab_benchmark('extremely_early_init') do
        program.extremely_early_init!
      end

      debug_check!(settings, program, 'raw1')

      dab_benchmark('very_early_init') do
        while true
          nop
          break unless program.very_early_init!
        end
      end

      debug_check!(settings, program, 'raw2')

      dab_benchmark('early_init') do
        while true
          nop
          break unless program.early_init!
        end
      end

      debug_check!(settings, program, 'rawinit1')

      dab_benchmark('init') do
        program.run_init!
      end

      debug_check!(settings, program, 'rawinit2')

      dab_benchmark('late_init') do
        while true
          nop
          break unless program.late_init!
        end
      end

      debug_check!(settings, program, 'rawinit3')

      dab_benchmark('box') do
        while true
          nop
          break unless program.box!
        end
      end

      debug_check!(settings, program, 'rawinit4')

      dab_benchmark('process') do
        last_functions = []
        index = 0
        while true
          index += 1
          all_functions = program.all_functions

          new_functions = all_functions - last_functions
          break if new_functions.count == 0

          last_functions = all_functions

          new_functions.each do |node|
            process_node(node)
            break if node.has_errors?
          end

          debug_check!(settings, program, "process step #{index}")
        end
      end

      debug_check!(settings, program, 'post')

      if $strip
        dab_benchmark('strip') do
          program.all_functions.each(&:run_strip_processors!)
        end
      end

      $constants_strip = true
      if $constants_strip
        dab_benchmark('strip') do
          nodes = program.all_nodes([DabNodeConstant])
          nodes.each(&:run_strip_processors!)
        end
      end

      debug_check!(settings, program, 'strip')

      if program.has_errors?
        program.errors.each do |e|
          context.stderr.puts e.annotated_source(streams[e.source.source_file])
          context.stderr.puts sprintf('%s:%d: error E%04d: %s', e.source.source_file, e.source.source_line || -1, e.error_code, e.message)
        end
        context.exit(1)
      else
        # err ('~' * 80).yellow
        # err 'FINAL FORM'
        # program.dump
        # err ('~' * 80).yellow

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

  def source_units_for(settings)
    inputs = Array(settings[:inputs])
    inputs = [:stdin] if inputs.empty?
    inputs.map do |input|
      DabSourceUnit.new(input: input, syntax_profile: syntax_profile)
    end.freeze
  end

  def process_node(program)
    if $multipass
      process_node_single_phase(program, false)
      return if program.has_errors?

      while true
        if $debug
          err '--~'.blue * 50
          err ''
          err ' * unssa step *'
          err ''
          program.dump
        end
        next if program.run_unssa_processors!

        break
      end

      if $debug
        err ''
        err '--~'.green * 50
        err ''
        err ' * UN_SSA *'
        err ''
        program.dump
        err ''
        err '--~'.green * 50
        err ''
      end
      return if program.has_errors?
    end

    process_node_single_phase(program)
  end

  def process_node_single_phase(program, do_flatten = true)
    return if program.run_checks!

    dab_benchmark('ssa') do
      program.run_ssa_processors!
    end

    debug_check!(@settings, program, 'ssa')

    if $debug
      err ''
      err '--'
    end

    while true
      if $debug
        program.dump
        err ''
        err '--~'.yellow * 50
        err ''
      end
      break if program.run_checks!
      next if $opt && dab_benchmark('optimize') do
        program.run_optimize_processors!
      end
      next if dab_benchmark('lower') do
        program.run_lower_processors!
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
      next if do_flatten && dab_benchmark('flatten') do
        program.run_flatten_processors!
      end

      break
    end
  end
end

def run_dab_compiler(settings, context, syntax_profile: DabSyntaxProfile::LEGACY, source_units: nil)
  DabCompilerFrontend.new(syntax_profile: syntax_profile, source_units: source_units).run(settings, context)
rescue DabModernSyntaxDiagnosticError => e
  context.stderr.puts "compiler: #{e.diagnostic}"
  context.exit(2)
rescue DabUnsupportedSyntaxProfileError => e
  context.stderr.puts "compiler: #{e.message}"
  context.exit(2)
end
