require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tmpdir'

module Dab
  module UnsafeFfiCapabilitySmoke
    CommandResult = Struct.new(:stdout, :stderr, :exit_code, :timed_out, keyword_init: true) do
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
      attr_reader :stage, :details

      def initialize(stage:, details:)
        super("#{stage} failed")
        @stage = stage
        @details = details
      end
    end

    class Commands
      def initialize(root:, binary_directory: 'bin')
        @root = root
        @binary_directory = binary_directory
      end

      def compiler(source)
        [
          RbConfig.ruby,
          File.join(@root, 'src/compiler/compiler.rb'),
          '--with-attributes',
          '--with-reflection',
          source,
        ]
      end

      def assembler
        assembler = File.join(@root, 'src/tobinary/tobinary.rb')
        [RbConfig.ruby, '-e', 'STDOUT.binmode; load ARGV.shift', assembler]
      end

      def vm(bytecode, allow_unsafe_ffi:)
        executable = "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}"
        command = [File.join(@root, @binary_directory, executable)]
        command << '--allow-unsafe-ffi' if allow_unsafe_ffi
        command << bytecode
      end
    end

    class SystemExecutor
      TERMINATION_GRACE_SECONDS = 1

      def call(command, input:, chdir:, timeout:, environment: {})
        options = {chdir: chdir}
        options[:pgroup] = true unless Gem.win_platform?
        stdin, stdout, stderr, wait_thread = Open3.popen3(environment, *command, options)
        [stdin, stdout, stderr].each(&:binmode)
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }
        stdin.write(input) if input
        stdin.close

        timed_out = wait_thread.join(timeout).nil?
        terminate(wait_thread) if timed_out
        status = wait_thread.value
        CommandResult.new(
          stdout: stdout_reader.value,
          stderr: stderr_reader.value,
          exit_code: timed_out ? 124 : status_code(status),
          timed_out: timed_out
        )
      rescue SystemCallError => e
        CommandResult.new(stdout: '', stderr: e.message, exit_code: 127, timed_out: false)
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
      COMPILER_TIMEOUT = 30
      ASSEMBLER_TIMEOUT = 30
      VM_TIMEOUT = 10
      EXPECTED_RUNTIME_TRACE_PATTERNS = [
        /\Avm: predefine default classes\z/,
        /\AVM options: autorun yes raw no cov no\z/,
        /\Avm: newformat: h: \d+, d: \d+, s: \d+\z/,
        /\Avm: offset is \d+\z/,
        /\Avm: newformat: section \d+: name '[a-z]+' address (?:0x)?[0-9a-f]+\/\d+ length \d+\z/,
        /\Areadbin: \d+ symbol\(s\) to read\z/,
        /\Avm: add function <(?:__init_0|import_unsafe_ffi|main|unsafe_ffi_abs)>\.\z/,
        /\Avm: seek initial code pointer to \d+\z/,
        /\Avm: define defaults\z/,
        /\Avm: define default classes\z/,
        /\Avm: define default functions\z/,
        /\Avm: trying to initialize attributes\z/,
        /\Avm: initialize attributes \(__init_0\)\z/,
        /\Avm: VM destroyed!\z/,
        /\Avm: reset \$VM pointer\z/,
      ].freeze

      def initialize(root:, executor: SystemExecutor.new, commands: nil, environment: {},
                     temporary_directory_factory: nil, output: $stdout, error: $stderr,
                     windows: Gem.win_platform?)
        @root = File.expand_path(root)
        @executor = executor
        @commands = commands || Commands.new(root: @root)
        @environment = environment
        @temporary_directory_factory = temporary_directory_factory || method(:with_temporary_directory)
        @output = output
        @error = error
        @windows = windows
      end

      def run
        contract = load_contract
        @temporary_directory_factory.call do |directory|
          bytecode = build_bytecode(directory)
          denied = execute_vm(bytecode, allow_unsafe_ffi: false)
          validate_result('denied-by-default runtime contract', denied, contract.fetch('denied'))

          allowed = execute_vm(bytecode, allow_unsafe_ffi: true)
          platform = @windows ? 'windows' : 'unix'
          validate_result(
            "explicit-opt-in #{platform} runtime contract",
            allowed,
            contract.fetch('allowed').fetch(platform)
          )
        end
        @output.puts('unsafe FFI capability smoke: PASSED (default denied, explicit opt-in checked)')
        0
      rescue StageFailure => e
        report_stage_failure(e)
        e.result.exit_code.zero? ? 1 : e.result.exit_code
      rescue ContractFailure => e
        @error.puts("unsafe FFI capability smoke: FAILED during #{e.stage}")
        @error.puts(e.details)
        1
      rescue SystemCallError, JSON::ParserError, KeyError, TypeError => e
        @error.puts("unsafe FFI capability smoke: FAILED during setup: #{e.class}: #{e.message}")
        1
      end

    private

      def load_contract
        contract = JSON.parse(File.binread(File.join(@root, 'test/unsafe_ffi_capability/contract.json')))
        unless contract.keys.sort == %w[allowed denied]
          raise KeyError.new('contract fields must be allowed and denied')
        end
        unless contract.fetch('allowed').keys.sort == %w[unix windows]
          raise KeyError.new('allowed contract fields must be unix and windows')
        end

        [contract.fetch('denied'), *contract.fetch('allowed').values].each do |result|
          unless result.keys.sort == %w[exit_status stderr_line stdout]
            raise KeyError.new('result contract fields must be exit_status, stderr_line, and stdout')
          end
          raise TypeError.new('result exit_status must be an integer') unless result['exit_status'].is_a?(Integer)
          raise TypeError.new('result stdout must be a string') unless result['stdout'].is_a?(String)
          unless result['stderr_line'].is_a?(String)
            raise TypeError.new('result stderr_line must be a string')
          end
        end
        contract
      end

      def build_bytecode(directory)
        source = File.join(directory, 'unsafe ffi capability.dab')
        assembly = File.join(directory, 'unsafe ffi capability.dabca')
        bytecode = File.join(directory, 'unsafe ffi capability.dabcb')
        FileUtils.cp(File.join(@root, 'test/unsafe_ffi_capability/program.dab'), source)

        compiler = invoke('compiler', @commands.compiler(source), timeout: COMPILER_TIMEOUT)
        File.binwrite(assembly, compiler.stdout)
        assembler = invoke(
          'assembler', @commands.assembler, input: compiler.stdout, timeout: ASSEMBLER_TIMEOUT
        )
        File.binwrite(bytecode, assembler.stdout)
        bytecode
      end

      def execute_vm(bytecode, allow_unsafe_ffi:)
        @executor.call(
          @commands.vm(bytecode, allow_unsafe_ffi: allow_unsafe_ffi),
          input: nil,
          chdir: @root,
          timeout: VM_TIMEOUT,
          environment: @environment
        )
      end

      def invoke(stage, command, timeout:, input: nil)
        result = @executor.call(
          command,
          input: input,
          chdir: @root,
          timeout: timeout,
          environment: @environment
        )
        return result if result.success?

        raise StageFailure.new(stage: stage, command: command, result: result, timeout: timeout)
      end

      def validate_result(stage, actual, expected)
        expected_stderr_line = expected.fetch('stderr_line').b
        stderr_lines = actual.stderr.lines(chomp: true)
        unexpected_stderr_lines = stderr_lines.reject do |line|
          line == expected_stderr_line || EXPECTED_RUNTIME_TRACE_PATTERNS.any? { |pattern| pattern.match?(line) }
        end
        matches = !actual.timed_out && actual.exit_code == expected.fetch('exit_status') &&
                  actual.stdout == expected.fetch('stdout').b &&
                  stderr_lines.count(expected_stderr_line) == 1 && unexpected_stderr_lines.empty?
        return if matches

        raise ContractFailure.new(
          stage: stage,
          details: "expected exit #{expected.fetch('exit_status')}, stdout #{dump(expected.fetch('stdout'))}, " \
                   "one stderr line #{dump(expected_stderr_line)} and no unexpected diagnostics; " \
                   "got exit #{actual.exit_code}, " \
                   "timed_out=#{actual.timed_out}, stdout #{dump(actual.stdout)}, stderr #{dump(actual.stderr)}"
        )
      end

      def report_stage_failure(failure)
        timeout = failure.result.timed_out ? " (timed out after #{failure.timeout} seconds)" : ''
        @error.puts("unsafe FFI capability smoke: FAILED during #{failure.stage}#{timeout}")
        @error.puts("command: #{Shellwords.join(failure.command)}")
        @error.puts("exit status: #{failure.result.exit_code}")
        @error.puts("captured stdout: #{dump(failure.result.stdout)}")
        @error.puts("captured stderr: #{dump(failure.result.stderr)}")
      end

      def dump(value)
        value.to_s.b.dump
      end

      def with_temporary_directory(&block)
        Dir.mktmpdir('dab-unsafe-ffi-capability') do |owned_root|
          workspace = File.join(owned_root, 'workspace with spaces')
          Dir.mkdir(workspace)
          block.call(workspace)
        end
      end
    end
  end
end
