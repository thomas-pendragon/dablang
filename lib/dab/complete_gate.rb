require 'English'
require 'open3'

module Dab
  module CompleteGate
    CommandResult = Struct.new(:success, :exit_code) do
      def success?
        success
      end
    end

    class GeneratedDocumentationInspectionError < StandardError; end

    class GeneratedDocumentation
      TRACKED_PATHS = [
        'docs/vm/opcodes.md',
        'docs/classes.md',
        'docs/classes',
      ].freeze

      def initialize(root:)
        @root = root
      end

      def changed_paths
        output, error, status = Open3.capture3(
          'git', 'diff', '--name-only', '--no-renames', '-z', 'HEAD', '--', *TRACKED_PATHS,
          chdir: @root
        )
        unless status.success?
          raise GeneratedDocumentationInspectionError.new(
            "git diff failed with exit status #{status.exitstatus}: #{error.strip}"
          )
        end

        normalize_paths(output.split("\0"))
      rescue SystemCallError => e
        raise GeneratedDocumentationInspectionError.new(
          "git diff could not be executed: #{e.message}"
        )
      end

    private

      def normalize_paths(paths)
        paths.reject(&:empty?).map { |path| path.tr('\\', '/') }.uniq.sort
      end
    end

    class SystemExecutor
      def call(command, chdir:)
        success = system(*command, chdir: chdir)
        status = $CHILD_STATUS
        exit_code = status&.exitstatus || signal_exit_code(status) || 1
        CommandResult.new(success, exit_code)
      end

    private

      def signal_exit_code(status)
        return unless status&.signaled?

        128 + status.termsig
      end
    end

    class Runner
      PREFLIGHT_COMMAND = %w[ruby script/toolchain_preflight.rb].freeze
      INHERITED_GATE_COMMAND = %w[bundle exec rake].freeze
      RSPEC_COMMAND = %w[bundle exec rspec].freeze
      STAGES = [
        ['supported toolchain preflight', PREFLIGHT_COMMAND],
        ['inherited build, test, and documentation gate', INHERITED_GATE_COMMAND],
        ['Ruby RSpec suite', RSPEC_COMMAND],
      ].freeze

      def initialize(root:, executor: SystemExecutor.new, generated_documentation: nil, output: $stdout, error: $stderr)
        @root = root
        @executor = executor
        @generated_documentation = generated_documentation || GeneratedDocumentation.new(root: root)
        @output = output
        @error = error
      end

      def run
        changed_paths = @generated_documentation.changed_paths
        return preexisting_generated_documentation_failure(changed_paths) unless changed_paths.empty?

        STAGES.each do |name, command|
          unless run_stage(name, command)
            status = failure(name, command)
            report_generated_documentation_after_failed_stage(name)
            return status
          end

          changed_paths = @generated_documentation.changed_paths
          return generated_documentation_failure(name, changed_paths) unless changed_paths.empty?
        end

        announce(@output, 'complete validation gate: PASSED')
        0
      rescue GeneratedDocumentationInspectionError => e
        announce(@error, "complete validation gate: FAILED while inspecting tracked generated documentation (#{e.message})")
        1
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

      def preexisting_generated_documentation_failure(paths)
        announce(
          @error,
          'complete validation gate: FAILED before supported toolchain preflight; ' \
          'tracked generated documentation is already modified'
        )
        report_generated_documentation_paths(paths)
        announce(@error, 'complete validation gate: resolve these pre-existing changes, then rerun')
        1
      end

      def generated_documentation_failure(name, paths)
        announce(
          @error,
          "complete validation gate: FAILED after successful #{name}; tracked generated documentation changed"
        )
        report_generated_documentation_paths(paths)
        announce(
          @error,
          'complete validation gate: commit intentional regenerated outputs or fix generator reproducibility, then rerun'
        )
        1
      end

      def report_generated_documentation_after_failed_stage(name)
        paths = @generated_documentation.changed_paths
        return if paths.empty?

        announce(
          @error,
          "complete validation gate: tracked generated documentation also changed during failed #{name}"
        )
        report_generated_documentation_paths(paths)
      rescue GeneratedDocumentationInspectionError => e
        announce(
          @error,
          "complete validation gate: unable to inspect tracked generated documentation after failed #{name} (#{e.message})"
        )
      end

      def report_generated_documentation_paths(paths)
        paths.map { |path| path.tr('\\', '/') }.uniq.sort.each do |path|
          announce(@error, "  #{path}")
        end
      end

      def announce(stream, message)
        stream.puts message
        stream.flush
      end
    end
  end
end
