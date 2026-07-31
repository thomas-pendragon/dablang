require 'English'

module Dab
  module CompleteGate
    CommandResult = Struct.new(:success, :exit_code) do
      def success?
        success
      end
    end

    class SystemExecutor
      def call(command, chdir:)
        success = system(*command, chdir: chdir)
        CommandResult.new(success, $CHILD_STATUS.exitstatus || 1)
      end
    end

    class Runner
      PREFLIGHT_COMMAND = %w[ruby script/toolchain_preflight.rb].freeze
      INHERITED_GATE_COMMAND = %w[bundle exec rake].freeze

      def initialize(root:, executor: SystemExecutor.new, output: $stdout, error: $stderr)
        @root = root
        @executor = executor
        @output = output
        @error = error
      end

      def run
        unless run_stage('supported toolchain preflight', PREFLIGHT_COMMAND)
          return failure('supported toolchain preflight', PREFLIGHT_COMMAND)
        end
        unless run_stage('inherited build, test, and documentation gate', INHERITED_GATE_COMMAND)
          return failure('inherited build, test, and documentation gate', INHERITED_GATE_COMMAND)
        end

        announce(@output, 'complete validation gate: PASSED')
        0
      end

    private

      def run_stage(name, command)
        announce(@output, "complete validation gate: #{name}")
        @last_result = @executor.call(command, chdir: @root)
        @last_result.success?
      end

      def failure(name, command)
        announce(@error, "complete validation gate: FAILED during #{name} (#{command.join(' ')})")
        @last_result.exit_code
      end

      def announce(stream, message)
        stream.puts message
        stream.flush
      end
    end
  end
end
