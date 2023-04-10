require_relative './shared'

class DecompileSpec
  include BaseFrontend

  def read_test_file(fname)
    base_read_test_file(fname)
  end

  def extract_format_source(input, output)
    describe_action(input, output, 'extract input') do
      text = read_test_file(input)[:dab_input]
      File.open(output, 'wb') do |file|
        file << text << "\n"
      end
    end
  end

  def decompile(input, output, options)
    run_ruby_part(input, output, 'decompile', 'decompile', options)
  end

  def run_test(settings)
    input = settings[:input]
    test_output_dir = settings[:test_output_dir] || '.'
    test_prefix = settings[:test_output_prefix] || ''

    data = read_test_file(input)
    runvm = (data[:options] || '')['--vm']

    options = data[:options] || ''

    info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
    puts info
    FileUtils.mkdir_p(test_output_dir)

    inp = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.inp')).to_s
    asm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.asm')).to_s
    bin = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.bin')).to_s
    dab = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.dab')).to_s
    out = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.out')).to_s
    FileUtils.rm_f(out)

    extract_format_source(input, inp)
    compile_dab_to_asm(inp, asm, '')
    assemble(asm, bin)
    if runvm
      vm = Pathname.new(test_output_dir).join(test_prefix + File.basename(input).ext('.vm')).to_s
      run_options = '--entry=main --output=dumpvm'
      run_options += ' --verbose'
      execute(bin, vm, run_options)
      bin = vm
    end
    decompile(bin, dab, options)

    expected = data[:expected].strip

    actual = File.read(dab).strip
    begin
      compare_output(info, actual, expected)
    rescue DabCompareError
      raise unless $autofix

      new_data = data.dup
      new_data[:expected] = actual.strip
      write_new_testspec(input, new_data)
    end

    File.open(out, 'wb') { |f| f << '1' }
  end
end

if $settings[:input].downcase.end_with? '.test'
  DecompileSpec.new.run_test($settings)
end
