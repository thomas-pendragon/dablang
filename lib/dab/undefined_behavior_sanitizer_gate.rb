require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'rbconfig'
require 'shellwords'
require 'stringio'

require_relative 'legacy_source_vm_smoke'
require_relative 'toolchain_preflight'
require_relative 'unsafe_ffi_capability_smoke'

module Dab
  module UndefinedBehaviorSanitizerGate
    SUPPORTED_TRUSTED_ARTIFACTS = %w[
      native-target:cvm
      native-target:cdisasm
      native-target:cdumpcov
      native-target:cffitest
      source:test/undefined_behavior_sanitizer/signed_integer_overflow.cpp
      source:test/native/string_intptr_lifetime.cpp
      normal-control:signed-integer-overflow
      smoke:native-tool-version
      smoke:unsafe-ffi-default-denial-and-explicit-opt-in
      smoke:legacy-source-vm
    ].freeze

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
          wait_thread.join
          return
        end

        Process.kill('TERM', -wait_thread.pid)
        wait_thread.join(TERMINATION_GRACE_SECONDS)
        Process.kill('KILL', -wait_thread.pid) if process_group_alive?(wait_thread.pid)
        wait_thread.join
      rescue Errno::ESRCH
        wait_thread.join
      end

      def process_group_alive?(process_group_id)
        Process.kill(0, -process_group_id)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def status_code(status)
        status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
      end
    end

    class Runner
      MANIFEST_COMMAND = %w[bundle exec ruby script/test_suite_manifest.rb].freeze
      PREFLIGHT_COMMAND = %w[ruby script/toolchain_preflight.rb].freeze
      OWNED_DIRECTORIES = %w[
        build/undefined-behavior-sanitizer
        bin/undefined-behavior-sanitizer
      ].freeze
      GENERATED_CONTRACT_TIMEOUT = 30
      BUILD_TIMEOUT = 180
      TOOL_TIMEOUT = 10
      CANARY_EXIT_CODE = 86
      SANITIZER_REPORT = /(?:runtime error:|SUMMARY: UndefinedBehaviorSanitizer|UndefinedBehaviorSanitizer:DEADLYSIGNAL)/.freeze
      BASE_UBSAN_OPTIONS = [
        "exitcode=#{CANARY_EXIT_CODE}",
        'halt_on_error=1',
        'print_stacktrace=1',
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
        build_and_verify_canary_binaries
        run_undefined_behavior_canary
        run_string_intptr_lifetime_regression
        run_native_tool_smoke
        run_unsafe_ffi_capability_smoke
        run_legacy_source_vm_smoke
        announce(@output, 'UndefinedBehaviorSanitizer gate: PASSED')
        0
      rescue StageFailure => e
        report_stage_failure(e)
        failure_status(e.result.exit_code)
      rescue ContractFailure => e
        report_contract_failure(e)
        e.exit_code
      rescue Errno::ENOENT, Errno::EACCES, IOError, JSON::ParserError, KeyError, TypeError, RegexpError => e
        announce(@error, "UndefinedBehaviorSanitizer gate: FAILED during setup: #{e.class}: #{e.message}")
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
        @profile = @contract.undefined_behavior_sanitizer
        @instrumentation_pattern = Regexp.new(@profile.fetch('instrumentation_symbol'))
      end

      def validate_profile
        expected_platform = "#{@host_os}-#{@host_cpu}"
        unless @profile.fetch('platform') == expected_platform
          raise ContractFailure.new(
            stage: 'UndefinedBehaviorSanitizer platform precondition',
            details: "supported #{@profile.fetch('platform')}; current #{expected_platform}"
          )
        end

        unless @profile.fetch('configuration') == 'UBSan'
          contract_failure('UndefinedBehaviorSanitizer profile contract', 'configuration must remain UBSan')
        end
        unless @profile.fetch('premake_option') == '--undefined-behavior-sanitizer'
          contract_failure(
            'UndefinedBehaviorSanitizer profile contract',
            'Premake option must remain --undefined-behavior-sanitizer'
          )
        end

        validate_owned_directories
        require_flags(@profile.fetch('compile_flags'), required_compile_flags, 'compile')
        require_flags(@profile.fetch('link_flags'), ['-fsanitize=undefined'], 'link')
      end

      def validate_owned_directories
        actual = [@profile.fetch('build_directory'), @profile.fetch('binary_directory')]
        unless actual == OWNED_DIRECTORIES
          contract_failure(
            'UndefinedBehaviorSanitizer output-isolation contract',
            "owned directories must remain #{OWNED_DIRECTORIES.join(' and ')}"
          )
        end
        object_directory = @profile.fetch('object_directory')
        expected_object = File.join(@profile.fetch('build_directory'), 'obj', 'UBSan')
        unless object_directory == expected_object
          contract_failure(
            'UndefinedBehaviorSanitizer output-isolation contract',
            "object directory must remain #{expected_object}"
          )
        end
      end

      def required_compile_flags
        [
          '-fsanitize=undefined',
          '-fno-sanitize-recover=all',
          '-fno-omit-frame-pointer',
          '-fno-optimize-sibling-calls',
        ]
      end

      def require_flags(actual, required, kind)
        missing = required - actual
        return if missing.empty?

        contract_failure(
          'UndefinedBehaviorSanitizer profile contract',
          "#{kind} flags are missing: #{missing.join(', ')}"
        )
      end

      def validate_tools
        validate_clang_tool('C++', @profile.fetch('compiler'))
        validate_clang_tool('C', @profile.fetch('c_compiler'))
        execute_required(
          'UndefinedBehaviorSanitizer build-driver precondition',
          ['make', '--version'],
          timeout: TOOL_TIMEOUT
        )
        execute_required(
          'UndefinedBehaviorSanitizer metadata-tool precondition',
          [@profile.fetch('metadata_tool'), '--version'],
          timeout: TOOL_TIMEOUT
        )
        execute_required(
          'UndefinedBehaviorSanitizer offline-symbolizer precondition',
          [@profile.fetch('symbolizer_tool'), '--version'],
          timeout: TOOL_TIMEOUT
        )
        premake_result = execute_required(
          'UndefinedBehaviorSanitizer Premake precondition',
          [selected_premake, '--version'],
          timeout: TOOL_TIMEOUT
        )
        return if premake_result.stdout.include?(@contract.premake_version)

        contract_failure(
          'UndefinedBehaviorSanitizer Premake precondition',
          "selected Premake must report #{@contract.premake_version}"
        )
      end

      def validate_clang_tool(kind, command)
        result = execute_required(
          "UndefinedBehaviorSanitizer #{kind} compiler precondition",
          [command, '--version'],
          timeout: TOOL_TIMEOUT
        )
        pattern = /clang version #{Regexp.escape(@profile.fetch('compiler_version'))}(?:\.|\s)/i
        return if (result.stdout + result.stderr).match?(pattern)

        contract_failure(
          "UndefinedBehaviorSanitizer #{kind} compiler precondition",
          "#{command} must report Clang #{@profile.fetch('compiler_version')}.x"
        )
      end

      def clean_owned_outputs
        announce(@output, 'UndefinedBehaviorSanitizer gate: clean isolated outputs')
        OWNED_DIRECTORIES.each do |relative_path|
          FileUtils.rm_rf(File.join(@root, relative_path))
        end
      end

      def generate_build
        execute_required(
          'dedicated UndefinedBehaviorSanitizer build generation',
          [selected_premake, @profile.fetch('premake_option'), @contract.premake_action],
          timeout: GENERATED_CONTRACT_TIMEOUT
        )
      end

      def validate_generated_build
        announce(@output, 'UndefinedBehaviorSanitizer gate: generated build contract')
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
            '-g',
            *@profile.fetch('compile_flags'),
            *@profile.fetch('link_flags'),
          ]
          missing = required_fragments.reject { |fragment| makefile.include?(fragment) }
          next if missing.empty?

          contract_failure(
            'generated UndefinedBehaviorSanitizer build contract',
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
        execute_required('dedicated UndefinedBehaviorSanitizer native build', command, timeout: BUILD_TIMEOUT)
      end

      def verify_target_instrumentation
        announce(@output, 'UndefinedBehaviorSanitizer gate: instrumentation metadata proof')
        @profile.fetch('targets').each_value do |output_name|
          verify_instrumented(File.join(@profile.fetch('binary_directory'), output_name))
        end
      end

      def build_and_verify_canary_binaries
        canary_directory = File.join(@root, @profile.fetch('build_directory'), 'canary')
        FileUtils.mkdir_p(canary_directory)
        source = File.join(@root, 'test/undefined_behavior_sanitizer/signed_integer_overflow.cpp')
        @normal_control = File.join(canary_directory, 'normal-control')
        @canary = File.join(canary_directory, 'signed-integer-overflow')
        common_flags = %w[-Wall -Wextra -Werror -g -O1]

        execute_required(
          'normal non-UndefinedBehaviorSanitizer control build',
          [@profile.fetch('compiler'), *common_flags, source, '-o', @normal_control],
          timeout: TOOL_TIMEOUT
        )
        verify_uninstrumented(relative(@normal_control))

        execute_required(
          'controlled UndefinedBehaviorSanitizer canary build',
          [
            @profile.fetch('compiler'),
            *@profile.fetch('compile_flags'),
            *common_flags,
            source,
            *@profile.fetch('link_flags'),
            '-o', @canary
          ],
          timeout: TOOL_TIMEOUT
        )
        verify_instrumented(relative(@canary))
      end

      def verify_instrumented(relative_path)
        symbols = instrumentation_symbols(relative_path)
        return unless symbols.empty?

        contract_failure(
          'UndefinedBehaviorSanitizer instrumentation proof',
          "#{relative_path} has no symbol matching #{@profile.fetch('instrumentation_symbol')}"
        )
      end

      def verify_uninstrumented(relative_path)
        symbols = instrumentation_symbols(relative_path)
        if symbols.empty?
          announce(
            @output,
            'UndefinedBehaviorSanitizer gate: normal binary rejected by instrumentation proof'
          )
          return
        end

        contract_failure(
          'UndefinedBehaviorSanitizer negative instrumentation proof',
          "#{relative_path} unexpectedly contains #{symbols.join(', ')}"
        )
      end

      def instrumentation_symbols(relative_path)
        path = File.join(@root, relative_path)
        result = execute_required(
          "UndefinedBehaviorSanitizer metadata read for #{relative_path}",
          [@profile.fetch('metadata_tool'), '--symbols', '--wide', path],
          timeout: TOOL_TIMEOUT
        )
        result.stdout.scan(@instrumentation_pattern).uniq.sort
      end

      def run_undefined_behavior_canary
        announce(@output, 'UndefinedBehaviorSanitizer gate: controlled signed-integer-overflow canary')
        result = @executor.call(
          [@canary],
          chdir: @root,
          timeout: TOOL_TIMEOUT,
          environment: sanitizer_environment
        )
        expected_report = /runtime error: signed integer overflow: .* cannot be represented in type 'int'/
        expected_summary = /SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior/
        stack_trace = result.stderr.include?('#0')
        matches = result.exit_code == CANARY_EXIT_CODE && !result.timed_out && result.stdout.empty? &&
                  result.stderr.match?(expected_report) && result.stderr.match?(expected_summary) && stack_trace
        return if matches

        details = "expected exit #{CANARY_EXIT_CODE}, empty stdout, signed-integer-overflow report, summary, " \
                  "and stack trace; got exit #{result.exit_code}, timed_out=#{result.timed_out}, " \
                  "stdout=#{result.stdout.dump}, stderr=#{result.stderr.dump}"
        raise ContractFailure.new(stage: 'controlled UndefinedBehaviorSanitizer canary', details: details)
      end

      def run_string_intptr_lifetime_regression
        regression_directory = File.join(@root, @profile.fetch('build_directory'), 'regressions')
        FileUtils.mkdir_p(regression_directory)
        binary = File.join(regression_directory, 'string-intptr-lifetime')
        source = File.join(@root, 'test/native/string_intptr_lifetime.cpp')
        common_flags = %w[-std=c++11 -Wall -Wextra -Werror -pedantic -g -O1]
        execute_required(
          'String-to-IntPtr lifetime regression build',
          [
            @profile.fetch('compiler'),
            *@profile.fetch('compile_flags'),
            *common_flags,
            source,
            *@profile.fetch('link_flags'),
            '-o', binary
          ],
          timeout: TOOL_TIMEOUT
        )
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
            environment: sanitizer_environment
          )
          expected = "#{label} #{version}\n"
          next if result.stdout == expected && result.stderr.empty?

          contract_failure(
            "instrumented #{target} version smoke",
            "expected stdout #{expected.dump} and empty stderr; got #{result.stdout.dump} / #{result.stderr.dump}"
          )
        end
      end

      def run_unsafe_ffi_capability_smoke
        announce(@output, 'UndefinedBehaviorSanitizer gate: instrumented unsafe FFI capability smoke')
        commands = UnsafeFfiCapabilitySmoke::Commands.new(
          root: @root,
          binary_directory: @profile.fetch('binary_directory')
        )
        status = UnsafeFfiCapabilitySmoke::Runner.new(
          root: @root,
          commands: commands,
          environment: sanitizer_environment,
          output: @output,
          error: @error,
          windows: false
        ).run
        return if status.zero?

        contract_failure('instrumented unsafe FFI capability smoke', "capability smoke returned #{status}")
      end

      def run_legacy_source_vm_smoke
        announce(@output, 'UndefinedBehaviorSanitizer gate: instrumented legacy source-to-VM smoke')
        smoke_output = StringIO.new
        smoke_error = StringIO.new
        commands = LegacySourceVmSmoke::Commands.new(
          root: @root,
          binary_directory: @profile.fetch('binary_directory')
        )
        status = with_sanitizer_environment do
          LegacySourceVmSmoke::Runner.new(
            root: @root,
            commands: commands,
            output: smoke_output,
            error: smoke_error
          ).run
        end
        combined = smoke_output.string + smoke_error.string
        if combined.match?(SANITIZER_REPORT)
          raise ContractFailure.new(
            stage: 'instrumented legacy source-to-VM smoke',
            details: "sanitizer report detected: #{combined.dump}",
            exit_code: status
          )
        end
        return if status.zero?

        raise ContractFailure.new(
          stage: 'instrumented legacy source-to-VM smoke',
          details: "legacy smoke returned #{status}; stdout=#{smoke_output.string.dump}; " \
                   "stderr=#{smoke_error.string.dump}",
          exit_code: status
        )
      end

      def execute_required(stage, command, timeout:, environment: {})
        announce(@output, "UndefinedBehaviorSanitizer gate: #{stage}")
        result = @executor.call(command, chdir: @root, timeout: timeout, environment: environment)
        unless result.success?
          raise StageFailure.new(stage: stage, command: command, result: result, timeout: timeout)
        end
        if (result.stdout + result.stderr).match?(SANITIZER_REPORT)
          raise ContractFailure.new(stage: stage, details: 'sanitizer report detected despite a zero exit status')
        end

        result
      end

      def report_stage_failure(failure)
        timeout = failure.result.timed_out ? " (timed out after #{failure.timeout} seconds)" : ''
        announce(@error, "UndefinedBehaviorSanitizer gate: FAILED during #{failure.stage}#{timeout}")
        announce(@error, "command: #{Shellwords.join(failure.command)}")
        announce(@error, "exit status: #{failure.result.exit_code}")
        announce(@error, "captured stdout: #{failure.result.stdout.dump}")
        announce(@error, "captured stderr: #{failure.result.stderr.dump}")
      end

      def report_contract_failure(failure)
        announce(@error, "UndefinedBehaviorSanitizer gate: FAILED during #{failure.stage}")
        announce(@error, failure.details)
      end

      def sanitizer_environment
        {'UBSAN_OPTIONS' => BASE_UBSAN_OPTIONS.join(':')}
      end

      def with_sanitizer_environment
        selected_environment = sanitizer_environment
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
