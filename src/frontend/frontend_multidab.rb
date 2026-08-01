require_relative 'shared_noautorun'

$autorun = true if $autorun.nil?

class DabMultiSpec
  include BaseFrontend

  SNAPSHOT_CONTRACT = 'latest-code-data-and-next-ring'.freeze
  REGENERATED_SECTIONS = %w[symb symd fext clas ndat].freeze

  def read_test_file(fname)
    base_read_test_file(fname)
  end

  def extract_source(input, output, text)
    describe_action(input, output, 'extract source') do
      File.open(output, 'wb') do |file|
        file << text
      end
    end
  end

  def run(_settings)
    data = read_test_file(input)

    info = "Running test #{input.blue.bold} in directory #{test_output_dir.blue.bold}..."
    puts info
    FileUtils.mkdir_p(test_output_dir)

    level = 0
    last_vmo = nil
    multilevel_snapshot_verified = false

    all_bin = []

    out = temp_file('out')

    begin
      sym = :"level_#{level}"
      next_sym = :"level_#{level + 1}"
      is_final = !data[next_sym]

      lfile = "level#{level}"
      dab = temp_file("#{lfile}.dab")
      asm = temp_file("#{lfile}.dabca")
      bin = temp_file("#{lfile}.dabcb")
      bin_asm = temp_file("#{lfile}.dabcb.dabca")
      vmo = temp_file("#{lfile}.vm")
      vmoa = temp_file("#{lfile}.vm.dabca")

      extract_source(input, dab, data[sym])
      compile_options = ''
      compile_options += ' --with_reflection'
      all_bin.each do |base|
        compile_options += " --ring-base[]=#{base}"
      end
      compile_dab_to_asm(dab, asm, compile_options)
      assemble_options = ''
      assemble(asm, bin, assemble_options)
      disassemble(bin, bin_asm, '--with-headers')
      run_options = "--entry=level#{level}"
      snapshot_inputs = all_bin + [bin]
      unless is_final
        run_options += ' --output=dumpvm'
      end
      run_options += ' --verbose'
      execute(snapshot_inputs, vmo, run_options)

      if snapshot_contract?(data) && !is_final
        repeat_vmo = temp_file("#{lfile}.repeat.vm")
        execute(snapshot_inputs, repeat_vmo, run_options)
        verify_snapshot(snapshot_inputs, vmo, repeat_vmo, level)
        verify_missing_code_rejection(bin, level) if level.zero?
        multilevel_snapshot_verified = true if snapshot_inputs.length > 1
      end

      all_bin << vmo unless is_final

      unless is_final
        disassemble(vmo, vmoa, '--with-headers')
      end

      level += 1
      last_vmo = vmo
    end until is_final

    test_body = data[:expect]
    actual_body = File.read(last_vmo).strip
    begin
      if snapshot_contract?(data) && !multilevel_snapshot_verified
        snapshot_contract_error(level, 'no writer invocation received multiple code/data inputs')
      end
      compare_output(info, actual_body, test_body)
      File.open(out, 'wb') { |f| f << '1' }
    rescue DabCompareError
      raise
    end
  end

  def snapshot_contract?(data)
    value = data[:snapshot_contract]
    return false unless value
    return true if value == SNAPSHOT_CONTRACT

    snapshot_contract_error(0, "unknown contract #{value.inspect}")
  end

  def verify_snapshot(inputs, snapshot, repeat_snapshot, level)
    DabTestOutput.with_action('snapshot-writing contract') do
      first_bytes = File.binread(snapshot)
      repeat_bytes = File.binread(repeat_snapshot)
      snapshot_contract_error(level, 'repeated output differs') unless first_bytes == repeat_bytes

      input_binaries = inputs.map { |path| read_snapshot_binary(path, level) }
      output_binary = read_snapshot_binary(snapshot, level)
      input_sections = input_binaries.flat_map { |binary| binary[:sections] }
      output_sections = output_binary[:sections]

      latest_code = input_sections.rindex { |section| section[:name] == 'code' }
      snapshot_contract_error(level, 'input has no code section') unless latest_code
      latest_data = input_sections.rindex { |section| section[:name] == 'data' }
      snapshot_contract_error(level, 'input has no data section') unless latest_data

      retained = input_sections.each_with_index.filter_map do |section, index|
        next if REGENERATED_SECTIONS.include?(section[:name])
        next if section[:name] == 'code' && index != latest_code
        next if section[:name] == 'data' && index != latest_data

        section
      end
      retained_names = retained.map { |section| section[:name] }
      actual_prefix = output_sections.first(retained_names.length).map { |section| section[:name] }
      unless actual_prefix == retained_names
        snapshot_contract_error(
          level,
          "retained section order #{actual_prefix.inspect} differs from #{retained_names.inspect}"
        )
      end

      %w[code data].each do |name|
        count = output_sections.count { |section| section[:name] == name }
        snapshot_contract_error(level, "expected one #{name} section, got #{count}") unless count == 1
      end

      if inputs.length > 1
        %w[code data].each do |name|
          count = input_sections.count { |section| section[:name] == name }
          snapshot_contract_error(level, "expected multiple input #{name} sections, got #{count}") if count < 2
        end
      end

      %w[code data].each do |name|
        source = input_sections.reverse.find { |section| section[:name] == name }
        written = output_sections.find { |section| section[:name] == name }
        unless source[:payload] == written[:payload]
          snapshot_contract_error(level, "latest #{name} section payload was not selected")
        end
      end
    end
  end

  def read_snapshot_binary(path, level)
    bytes = File.binread(path)
    reader = DabBinReader.new
    header = reader.parse_whole_header_with_offset(bytes)
    snapshot_contract_error(level, 'invalid DAB header') unless header[:dab] == 'DAB' && header[:zero].zero?
    snapshot_contract_error(level, "unsupported DAB version #{header[:version]}") unless header[:version] == 3

    expected_header_size = 40 + (header[:sections_count] * 32)
    unless header[:size_of_header] == expected_header_size
      snapshot_contract_error(level, 'header size does not match section count')
    end
    unless header[:size_of_header] + header[:size_of_data] == bytes.bytesize
      snapshot_contract_error(level, 'header and data sizes do not match file size')
    end

    next_position = header[:size_of_header]
    sections = header[:sections].map do |section|
      snapshot_contract_error(level, "section #{section[:name]} is not contiguous") unless section[:address] == next_position
      section_end = section[:address] + section[:length]
      snapshot_contract_error(level, "section #{section[:name]} exceeds snapshot size") if section_end > bytes.bytesize
      next_position = section_end
      section.merge(payload: bytes.byteslice(section[:address], section[:length]))
    end
    snapshot_contract_error(level, 'section lengths do not consume snapshot data') unless next_position == bytes.bytesize

    {header: header, sections: sections}
  rescue StandardError => e
    raise if e.is_a?(DabCompareError)

    snapshot_contract_error(level, "cannot parse snapshot: #{e.class}: #{e.message}")
  end

  def verify_missing_code_rejection(binary_path, level)
    DabTestOutput.with_action('snapshot-writing malformed-input contract') do
      begin
        malformed_path = temp_file("level#{level}.missing-code.dabcb")
        output_path = temp_file("level#{level}.missing-code.vm")
        bytes = File.binread(binary_path)
        header = DabBinReader.new.parse_whole_header(bytes)
        code_index = header[:sections].index { |section| section[:name] == 'code' }
        snapshot_contract_error(level, 'negative probe source has no code section') unless code_index
        bytes[40 + (code_index * 32), 4] = 'noop'
        File.binwrite(malformed_path, bytes)

        command = [
          './bin/cvm', "--entry=level#{level}", '--output=dumpvm', malformed_path, "--out=#{output_path}"
        ]
        stdout, stderr, status = Open3.capture3(*command)
        expected = "vm/binsave: snapshot-writing stage failed: no code section available\n"
        unless status.exitstatus == 1 && stdout.empty? && stderr.end_with?(expected)
          snapshot_contract_error(
            level,
            "missing-code rejection was exit #{status.exitstatus.inspect}, stdout #{stdout.dump}, stderr #{stderr.dump}"
          )
        end
      ensure
        FileUtils.rm_f(malformed_path) if malformed_path
        FileUtils.rm_f(output_path) if output_path
      end
    end
  end

  def snapshot_contract_error(level, message)
    raise DabCompareError.new("snapshot-writing contract level #{level}: #{message}")
  end
end

if $autorun
  read_args!
  raise 'no test' unless $settings[:input].downcase.end_with?('.test')

  test = DabMultiSpec.new
  test.run_test($settings)
end
