require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'rbconfig'
require 'shellwords'
require 'stringio'

require_relative 'legacy_source_vm_smoke'
require_relative 'toolchain_preflight'

module Dab
  module AddressSanitizerGate
    CommandResult = Struct.new(:stdout, :stderr, :exit_code, :timed_out) do
      def success?
        exit_code.zero? && !timed_out
      end
    end

    class StageFailure < StandardError
      attr_reader :stage, :command, :result, :timeout

      def initialize(stage:, command:, result:, timeout:)
        super("#{stage} failed")
        @stage = stage
        @command = command
        @result = result
        @timeout = timeout
      end
    end

    class ContractFailure < StandardError
      attr_reader :stage, :details, :exit_code

      def initialize(stage:, details:, exit_code: 1)
        super("#{stage} failed")
        @stage = stage
        @details = details
        @exit_code = exit_code.zero? ? 1 : exit_code
      end
    end

    class SystemExecutor
      TERMINATION_GRACE_SECONDS = 1

      def call(command, chdir:, timeout:, environment: {})
        options = {chdir: chdir}
        options[:pgroup] = true unless Gem.win_platform?
        stdin, stdout, stderr, wait_thread = Open3.popen3(environment, *command, options)
        stdin.close
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }
        timed_out = wait_thread.join(timeout).nil?
        terminate(wait_thread) if timed_out
        status = wait_thread.value
        CommandResult.new(
          stdout_reader.value,
          stderr_reader.value,
          timed_out ? 124 : status_code(status),
          timed_out
        )
      rescue SystemCallError => e
        CommandResult.new('', e.message, 127, false)
      ensure
        [stdin, stdout, stderr].compact.each { |stream| stream.close unless stream.closed? }
      end

    private

      def terminate(wait_thread)
        if Gem.win_platform?
          system('taskkill', '/PID', wait_thread.pid.to_s, '/T', '/F', out: File::NULL, err: File::NULL)
        else
          Process.kill('TERM', -wait_thread.pid)
          Process.kill('KILL', -wait_thread.pid) unless wait_thread.join(TERMINATION_GRACE_SECONDS)
        end
        wait_thread.join
      rescue Errno::ESRCH
        nil
      end

      def status_code(status)
        status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
      end
    end

    class Runner
      MANIFEST_COMMAND = %w[bundle exec ruby script/test_suite_manifest.rb].freeze
      PREFLIGHT_COMMAND = %w[ruby script/toolchain_preflight.rb].freeze
      OWNED_DIRECTORIES = %w[build/address-sanitizer bin/address-sanitizer].freeze
      GENERATED_CONTRACT_TIMEOUT = 30
      BUILD_TIMEOUT = 180
      TOOL_TIMEOUT = 10
      CANARY_EXIT_CODE = 86
      SANITIZER_REPORT = /(?:ERROR|SUMMARY): (?:AddressSanitizer|LeakSanitizer)/.freeze
      BASE_ASAN_OPTIONS = [
        'abort_on_error=0',
        'check_initialization_order=1',
        'detect_odr_violation=2',
        'detect_stack_use_after_return=1',
        "exitcode=#{CANARY_EXIT_CODE}",
        'halt_on_error=1',
        'strict_string_checks=1',
        'symbolize=0',
      ].freeze
      VERSION_LABELS = {
        'cvm' => 'Dab VM',
        'cdisasm' => 'Dab disassembler',
        'cdumpcov' => 'Dab coverage dumper',
      }.freeze

      def initialize(root:, executor: SystemExecutor.new, environment: ENV, output: $stdout, error: $stderr,
                     host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
        @root = File.expand_path(root)
        @executor = executor
        @environment = environment
        @output = output
        @error = error
        @host_os = ToolchainPreflight::Platform.os(host_os)
        @host_cpu = ToolchainPreflight::Platform.architecture(host_cpu)
      end

      def run
        load_contract
        execute_required('test suite manifest validation', MANIFEST_COMMAND, timeout: TOOL_TIMEOUT)
        execute_required('supported toolchain preflight', PREFLIGHT_COMMAND, timeout: TOOL_TIMEOUT)
        validate_profile
        validate_tools
        clean_owned_outputs
        generate_build
        validate_generated_build
        build_targets
        verify_target_instrumentation
        run_memory_error_canary
        run_string_intptr_lifetime_regression
        run_native_tool_smoke
        run_legacy_source_vm_smoke
        announce(@output, 'AddressSanitizer gate: PASSED')
        0
      rescue StageFailure => e
        report_stage_failure(e)
        failure_status(e.result.exit_code)
      rescue ContractFailure => e
        report_contract_failure(e)
        e.exit_code
      rescue Errno::ENOENT, Errno::EACCES, IOError, JSON::ParserError, KeyError, TypeError => e
        announce(@error, "AddressSanitizer gate: FAILED during setup: #{e.class}: #{e.message}")
        1
      end

    private

      def load_contract
        path = File.join(@root, 'config/supported_toolchain.json')
        @contract = ToolchainPreflight::Contract.load(path)
        unless @contract.valid_structure?
          raise ContractFailure.new(
            stage: 'supported-toolchain profile contract',
            details: 'config/supported_toolchain.json does not match schema version ' \
                     "#{ToolchainPreflight::Contract::SCHEMA_VERSION}"
          )
        end
        @profile = @contract.address_sanitizer
      end

      def validate_profile
        expected_platform = "#{@host_os}-#{@host_cpu}"
        unless @profile.fetch('platform') == expected_platform
          raise ContractFailure.new(
            stage: 'AddressSanitizer platform precondition',
            details: "supported #{@profile.fetch('platform')}; current #{expected_platform}"
          )
        end

        unless @profile.fetch('configuration') == 'ASan'
          contract_failure('AddressSanitizer profile contract', 'configuration must remain ASan')
        end
        unless @profile.fetch('premake_option') == '--address-sanitizer'
          contract_failure('AddressSanitizer profile contract', 'Premake option must remain --address-sanitizer')
        end
        unless @profile.fetch('leak_detection') == true
          contract_failure('AddressSanitizer profile contract', 'leak detection must remain enabled')
        end

        validate_owned_directories
        require_flags(@profile.fetch('compile_flags'), required_compile_flags, 'compile')
        require_flags(@profile.fetch('link_flags'), ['-fsanitize=address'], 'link')
      end

      def validate_owned_directories
        actual = [@profile.fetch('build_directory'), @profile.fetch('binary_directory')]
        unless actual == OWNED_DIRECTORIES
          contract_failure(
            'AddressSanitizer output-isolation contract',
            "owned directories must remain #{OWNED_DIRECTORIES.join(' and ')}"
          )
        end
        object_directory = @profile.fetch('object_directory')
        expected_object = File.join(@profile.fetch('build_directory'), 'obj', 'ASan')
        unless object_directory == expected_object
          contract_failure(
            'AddressSanitizer output-isolation contract',
            "object directory must remain #{expected_object}"
          )
        end
      end

      def required_compile_flags
        [
          '-fsanitize=address',
          '-fsanitize-address-use-after-scope',
          '-fno-omit-frame-pointer',
          '-fno-optimize-sibling-calls',
        ]
      end

      def require_flags(actual, required, kind)
        missing = required - actual
        return if missing.empty?

        contract_failure(
          'AddressSanitizer profile contract',
          "#{kind} flags are missing: #{missing.join(', ')}"
        )
      end

      def validate_tools
        compiler = execute_required(
          'AddressSanitizer C++ compiler precondition',
          [@profile.fetch('compiler'), '--version'],
          timeout: TOOL_TIMEOUT
        )
        compiler_pattern = /clang version #{Regexp.escape(@profile.fetch('compiler_version'))}(?:\.|\s)/
        unless compiler.stdout.match?(compiler_pattern)
          contract_failure(
            'AddressSanitizer C++ compiler precondition',
            "#{@profile.fetch('compiler')} must report Clang #{@profile.fetch('compiler_version')}.x"
          )
        end
        execute_required(
          'AddressSanitizer C compiler precondition',
          [@profile.fetch('c_compiler'), '--version'],
          timeout: TOOL_TIMEOUT
        )
        execute_required(
          'AddressSanitizer build-driver precondition',
          ['make', '--version'],
          timeout: TOOL_TIMEOUT
        )
        execute_required(
          'AddressSanitizer metadata-tool precondition',
          [@profile.fetch('metadata_tool'), '--version'],
          timeout: TOOL_TIMEOUT
        )
        premake = selected_premake
        premake_result = execute_required(
          'AddressSanitizer Premake precondition',
          [premake, '--version'],
          timeout: TOOL_TIMEOUT
        )
        unless premake_result.stdout.include?(@contract.premake_version)
          contract_failure(
            'AddressSanitizer Premake precondition',
            "selected Premake must report #{@contract.premake_version}"
          )
        end
      end

      def clean_owned_outputs
        announce(@output, 'AddressSanitizer gate: clean isolated outputs')
        OWNED_DIRECTORIES.each do |relative_path|
          FileUtils.rm_rf(File.join(@root, relative_path))
        end
      end

      def generate_build
        execute_required(
          'dedicated AddressSanitizer build generation',
          [selected_premake, @profile.fetch('premake_option'), @contract.premake_action],
          timeout: GENERATED_CONTRACT_TIMEOUT
        )
      end

      def validate_generated_build
        announce(@output, 'AddressSanitizer gate: generated build contract')
        build_directory = File.join(@root, @profile.fetch('build_directory'))
        @profile.fetch('targets').each do |target, output_name|
          makefile_path = File.join(build_directory, "#{target}.make")
          makefile = File.binread(makefile_path)
          expected_target = Pathname.new(File.join(@root, @profile.fetch('binary_directory'), output_name))
                                    .relative_path_from(Pathname.new(build_directory)).to_s
          expected_object = File.join('obj', @profile.fetch('configuration'), target)
          required_fragments = [
            "TARGETDIR = #{File.dirname(expected_target)}",
            "TARGET = $(TARGETDIR)/#{File.basename(expected_target)}",
            "OBJDIR = #{expected_object}",
            '-Werror',
            *@profile.fetch('compile_flags'),
            *@profile.fetch('link_flags'),
          ]
          missing = required_fragments.reject { |fragment| makefile.include?(fragment) }
          next if missing.empty?

          contract_failure(
            'generated AddressSanitizer build contract',
            "#{relative(makefile_path)} is missing #{missing.uniq.join(', ')}"
          )
        end
      end

      def build_targets
        command = [
          'make', '-C', @profile.fetch('build_directory'),
          "config=#{@profile.fetch('configuration').downcase}", '-j2',
          "CC=#{@profile.fetch('c_compiler')}", "CXX=#{@profile.fetch('compiler')}",
          *@profile.fetch('targets').keys,
          'verbose=1'
        ]
        execute_required('dedicated AddressSanitizer native build', command, timeout: BUILD_TIMEOUT)
      end

      def verify_target_instrumentation
        announce(@output, 'AddressSanitizer gate: instrumentation metadata proof')
        @profile.fetch('targets').each_value do |output_name|
          verify_instrumented(File.join(@profile.fetch('binary_directory'), output_name))
        end
      end

      def verify_instrumented(relative_path)
        path = File.join(@root, relative_path)
        result = execute_required(
          "AddressSanitizer metadata read for #{relative_path}",
          [@profile.fetch('metadata_tool'), '--symbols', '--wide', path],
          timeout: TOOL_TIMEOUT,
          replay: false
        )
        return if result.stdout.include?(@profile.fetch('instrumentation_symbol'))

        contract_failure(
          'AddressSanitizer instrumentation proof',
          "#{relative_path} has no #{@profile.fetch('instrumentation_symbol')} symbol"
        )
      end

      def run_memory_error_canary
        canary_directory = File.join(@root, @profile.fetch('build_directory'), 'canary')
        FileUtils.mkdir_p(canary_directory)
        canary = File.join(canary_directory, 'heap-buffer-overflow')
        source = File.join(@root, 'test/address_sanitizer/heap_buffer_overflow.cpp')
        command = [
          @profile.fetch('compiler'),
          *@profile.fetch('compile_flags'),
          '-g', '-O1', source,
          *@profile.fetch('link_flags'),
          '-o', canary
        ]
        execute_required('controlled AddressSanitizer canary build', command, timeout: TOOL_TIMEOUT)
        verify_instrumented(relative(canary))

        announce(@output, 'AddressSanitizer gate: controlled heap-buffer-overflow canary')
        result = @executor.call(
          [canary],
          chdir: @root,
          timeout: TOOL_TIMEOUT,
          environment: sanitizer_environment
        )
        expected_report = /ERROR: AddressSanitizer: heap-buffer-overflow/
        return if result.exit_code == CANARY_EXIT_CODE && result.stderr.match?(expected_report) && !result.timed_out

        details = "expected exit #{CANARY_EXIT_CODE} and heap-buffer-overflow report; " \
                  "got exit #{result.exit_code}, timed_out=#{result.timed_out}, stderr=#{result.stderr.dump}"
        raise ContractFailure.new(stage: 'controlled AddressSanitizer canary', details: details)
      end

      def run_string_intptr_lifetime_regression
        regression_directory = File.join(@root, @profile.fetch('build_directory'), 'regressions')
        FileUtils.mkdir_p(regression_directory)
        binary = File.join(regression_directory, 'string-intptr-lifetime')
        source = File.join(@root, 'test/native/string_intptr_lifetime.cpp')
        command = [
          @profile.fetch('compiler'),
          *@profile.fetch('compile_flags'),
          '-std=c++11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-g', '-O1',
          source,
          *@profile.fetch('link_flags'),
          '-o', binary
        ]
        execute_required('String-to-IntPtr lifetime regression build', command, timeout: TOOL_TIMEOUT)
        verify_instrumented(relative(binary))
        execute_required(
          'String-to-IntPtr lifetime regression',
          [binary],
          timeout: TOOL_TIMEOUT,
          environment: sanitizer_environment
        )
      end

      def run_native_tool_smoke
        version = File.binread(File.join(@root, 'VERSION')).strip
        VERSION_LABELS.each do |target, label|
          relative_path = File.join(@profile.fetch('binary_directory'), @profile.fetch('targets').fetch(target))
          result = execute_required(
            "instrumented #{target} version smoke",
            [File.join(@root, relative_path), '--version'],
            timeout: TOOL_TIMEOUT,
            environment: sanitizer_environment,
            replay: false
          )
          expected = "#{label} #{version}\n"
          next if result.stdout == expected && result.stderr.empty?

          contract_failure(
            "instrumented #{target} version smoke",
            "expected stdout #{expected.dump} and empty stderr; got #{result.stdout.dump} / #{result.stderr.dump}"
          )
        end
      end

      def run_legacy_source_vm_smoke
        announce(@output, 'AddressSanitizer gate: instrumented legacy source-to-VM smoke')
        status, smoke_output, smoke_error = capture_legacy_smoke(detect_leaks: true)
        @output.write(smoke_output.string)
        @error.write(smoke_error.string)
        @output.flush
        @error.flush
        combined = smoke_output.string + smoke_error.string
        if combined.match?(SANITIZER_REPORT)
          raise ContractFailure.new(
            stage: 'instrumented legacy source-to-VM smoke',
            details: 'sanitizer report detected in captured diagnostics',
            exit_code: status
          )
        end
        return if status.zero?

        raise ContractFailure.new(
          stage: 'instrumented legacy source-to-VM smoke',
          details: "legacy smoke returned #{status}",
          exit_code: status
        )
      end

      def capture_legacy_smoke(detect_leaks:)
        smoke_output = StringIO.new
        smoke_error = StringIO.new
        commands = LegacySourceVmSmoke::Commands.new(
          root: @root,
          binary_directory: @profile.fetch('binary_directory')
        )
        status = with_sanitizer_environment(detect_leaks: detect_leaks) do
          LegacySourceVmSmoke::Runner.new(
            root: @root,
            commands: commands,
            output: smoke_output,
            error: smoke_error
          ).run
        end
        [status, smoke_output, smoke_error]
      end

      def execute_required(stage, command, timeout:, environment: {}, replay: true)
        announce(@output, "AddressSanitizer gate: #{stage}")
        result = @executor.call(command, chdir: @root, timeout: timeout, environment: environment)
        replay_result(result) if replay
        unless result.success?
          raise StageFailure.new(stage: stage, command: command, result: result, timeout: timeout)
        end
        if (result.stdout + result.stderr).match?(SANITIZER_REPORT)
          raise ContractFailure.new(stage: stage, details: 'sanitizer report detected despite a zero exit status')
        end

        result
      end

      def replay_result(result)
        @output.write(result.stdout)
        @error.write(result.stderr)
        @output.flush
        @error.flush
      end

      def report_stage_failure(failure)
        timeout = failure.result.timed_out ? " (timed out after #{failure.timeout} seconds)" : ''
        announce(@error, "AddressSanitizer gate: FAILED during #{failure.stage}#{timeout}")
        announce(@error, "command: #{Shellwords.join(failure.command)}")
        announce(@error, "exit status: #{failure.result.exit_code}")
        announce(@error, "captured stdout: #{failure.result.stdout.dump}")
        announce(@error, "captured stderr: #{failure.result.stderr.dump}")
      end

      def report_contract_failure(failure)
        announce(@error, "AddressSanitizer gate: FAILED during #{failure.stage}")
        announce(@error, failure.details)
      end

      def sanitizer_environment(detect_leaks: true)
        {
          'ASAN_OPTIONS' => (BASE_ASAN_OPTIONS + ["detect_leaks=#{detect_leaks ? 1 : 0}"]).join(':'),
          'LSAN_OPTIONS' => "exitcode=#{CANARY_EXIT_CODE}",
        }
      end

      def with_sanitizer_environment(detect_leaks: true)
        selected_environment = sanitizer_environment(detect_leaks: detect_leaks)
        previous = selected_environment.keys.map { |key| [key, ENV.fetch(key, nil)] }.to_h
        selected_environment.each { |key, value| ENV[key] = value }
        yield
      ensure
        previous.each do |key, value|
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
      end

      def selected_premake
        @environment['PREMAKE'] || 'premake5'
      end

      def relative(path)
        Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
      end

      def failure_status(status)
        status.zero? ? 1 : status
      end

      def contract_failure(stage, details)
        raise ContractFailure.new(stage: stage, details: details)
      end

      def announce(stream, message)
        stream.puts(message)
        stream.flush
      end
    end
  end
end
