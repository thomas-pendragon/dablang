require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tmpdir'

module Dab
  module LegacySourceVmSmoke
    CommandResult = Struct.new(:stdout, :stderr, :exit_code, :timed_out, keyword_init: true) do
      def success?
        exit_code.zero? && !timed_out
      end
    end

    SmokeResult = Struct.new(:bytecode, :stdout, :stderr, :exit_code, keyword_init: true)

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
        [RbConfig.ruby, File.join(@root, 'src/compiler/compiler.rb'), source]
      end

      def assembler
        [RbConfig.ruby, File.join(@root, 'src/tobinary/tobinary.rb')]
      end

      def vm(bytecode)
        executable = "cvm#{RbConfig::CONFIG.fetch('EXEEXT')}"
        [File.join(@root, @binary_directory, executable), bytecode]
      end
    end

    class SystemExecutor
      TERMINATION_GRACE_SECONDS = 1

      def call(command, input:, chdir:, timeout:)
        options = {chdir: chdir}
        options[:pgroup] = true unless Gem.win_platform?
        stdin, stdout, stderr, wait_thread = Open3.popen3(*command, options)
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
          terminate_windows(wait_thread.pid)
        else
          terminate_unix(wait_thread)
        end
        wait_thread.join
      end

      def terminate_windows(pid)
        system('taskkill', '/PID', pid.to_s, '/T', '/F', out: File::NULL, err: File::NULL)
      rescue SystemCallError
        Process.kill('KILL', pid)
      end

      def terminate_unix(wait_thread)
        Process.kill('TERM', -wait_thread.pid)
        return if wait_thread.join(TERMINATION_GRACE_SECONDS)

        Process.kill('KILL', -wait_thread.pid)
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
      TEMPORARY_PREFIX = 'dab-legacy-source-vm-smoke'.freeze
      TEMPORARY_WORKSPACE = 'workspace with spaces'.freeze
      SOURCE_NAME = 'legacy smoke program.dab'.freeze
      ASSEMBLY_NAME = 'legacy smoke program.dabca'.freeze
      BYTECODE_NAME = 'legacy smoke program.dabcb'.freeze

      def initialize(root:, executor: SystemExecutor.new, commands: nil, temporary_directory_factory: nil,
                     output: $stdout, error: $stderr)
        @root = File.expand_path(root)
        @executor = executor
        @commands = commands || Commands.new(root: @root)
        @temporary_directory_factory = temporary_directory_factory || method(:with_temporary_directory)
        @output = output
        @error = error
      end

      def run
        contract = load_contract
        first = run_in_independent_directory
        second = run_in_independent_directory
        validate_reproducibility(first, second)
        validate_runtime_contract(first, second, contract)
        digest = Digest::SHA256.hexdigest(first.bytecode)
        @output.puts(
          'legacy source-to-VM smoke: PASSED ' \
          "(2 runs, #{first.bytecode.bytesize} byte portable bytecode, sha256 #{digest})"
        )
        0
      rescue StageFailure => e
        report_stage_failure(e)
        failure_status(e.result.exit_code)
      rescue ContractFailure => e
        report_contract_failure(e)
        1
      rescue SystemCallError, JSON::ParserError, KeyError, TypeError => e
        @error.puts("legacy source-to-VM smoke: FAILED during smoke setup: #{e.class}: #{e.message}")
        1
      end

    private

      def load_contract
        path = File.join(@root, 'test/legacy_source_vm_smoke/contract.json')
        contract = JSON.parse(File.binread(path))
        expected_fields = %w[exit_status stderr stdout]
        unless contract.keys.sort == expected_fields
          raise KeyError.new("contract fields must be #{expected_fields.join(', ')}")
        end
        raise TypeError.new('contract stdout must be a string') unless contract['stdout'].is_a?(String)
        unless contract['stderr'] == 'identical-across-runs'
          raise TypeError.new('contract stderr must be identical-across-runs')
        end
        unless contract['exit_status'].is_a?(Integer)
          raise TypeError.new('contract exit_status must be an integer')
        end

        contract
      end

      def run_in_independent_directory
        @temporary_directory_factory.call do |directory|
          source = File.join(directory, SOURCE_NAME)
          assembly = File.join(directory, ASSEMBLY_NAME)
          bytecode = File.join(directory, BYTECODE_NAME)
          FileUtils.cp(File.join(@root, 'test/legacy_source_vm_smoke/program.dab'), source)

          compiler = invoke('compiler', @commands.compiler(source), timeout: COMPILER_TIMEOUT)
          File.binwrite(assembly, compiler.stdout)
          assembler = invoke(
            'assembler', @commands.assembler, input: compiler.stdout, timeout: ASSEMBLER_TIMEOUT
          )
          File.binwrite(bytecode, assembler.stdout)
          vm = invoke('native VM', @commands.vm(bytecode), timeout: VM_TIMEOUT)
          SmokeResult.new(
            bytecode: assembler.stdout,
            stdout: vm.stdout,
            stderr: vm.stderr,
            exit_code: vm.exit_code
          )
        end
      end

      def invoke(stage, command, timeout:, input: nil)
        result = @executor.call(command, input: input, chdir: @root, timeout: timeout)
        return result if result.success?

        raise StageFailure.new(stage: stage, command: command, result: result, timeout: timeout)
      end

      def validate_reproducibility(first, second)
        return if !first.bytecode.empty? && first.bytecode == second.bytecode

        details = if first.bytecode.empty?
                    'assembler produced empty portable bytecode'
                  else
                    first_digest = Digest::SHA256.hexdigest(first.bytecode)
                    second_digest = Digest::SHA256.hexdigest(second.bytecode)
                    "bytecode differs: run 1 sha256 #{first_digest}, run 2 sha256 #{second_digest}"
                  end
        raise ContractFailure.new(stage: 'bytecode reproducibility contract', details: details)
      end

      def validate_runtime_contract(first, second, contract)
        expected_status = contract.fetch('exit_status')
        unless first.exit_code == expected_status && second.exit_code == expected_status
          raise ContractFailure.new(
            stage: 'runtime exit-status contract',
            details: "expected #{expected_status}; got run 1 #{first.exit_code}, run 2 #{second.exit_code}"
          )
        end

        expected_stdout = contract.fetch('stdout').b
        unless first.stdout == expected_stdout && second.stdout == expected_stdout
          raise ContractFailure.new(
            stage: 'runtime stdout contract',
            details: "expected #{dump(expected_stdout)}; got run 1 #{dump(first.stdout)}, run 2 #{dump(second.stdout)}"
          )
        end

        return if first.stderr == second.stderr

        raise ContractFailure.new(
          stage: 'runtime stderr contract',
          details: "expected identical stderr; got run 1 #{dump(first.stderr)}, run 2 #{dump(second.stderr)}"
        )
      end

      def report_stage_failure(failure)
        timeout = failure.result.timed_out ? " (timed out after #{failure.timeout} seconds)" : ''
        @error.puts("legacy source-to-VM smoke: FAILED during #{failure.stage}#{timeout}")
        @error.puts("command: #{Shellwords.join(failure.command)}")
        @error.puts("exit status: #{failure.result.exit_code}")
        @error.puts("captured stdout: #{dump(failure.result.stdout)}")
        @error.puts("captured stderr: #{dump(failure.result.stderr)}")
      end

      def report_contract_failure(failure)
        @error.puts("legacy source-to-VM smoke: FAILED during #{failure.stage}")
        @error.puts(failure.details)
      end

      def failure_status(status)
        status.zero? ? 1 : status
      end

      def dump(value)
        value.to_s.b.dump
      end

      def with_temporary_directory(&block)
        Dir.mktmpdir(TEMPORARY_PREFIX) do |owned_root|
          workspace = File.join(owned_root, TEMPORARY_WORKSPACE)
          Dir.mkdir(workspace)
          block.call(workspace)
        end
      end
    end
  end
end
