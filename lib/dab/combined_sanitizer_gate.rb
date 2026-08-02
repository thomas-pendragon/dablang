require 'json'
require 'rbconfig'
require 'yaml'

require_relative 'address_sanitizer_gate'
require_relative 'toolchain_preflight'
require_relative 'undefined_behavior_sanitizer_gate'

module Dab
  module CombinedSanitizerGate
    class ContractFailure < StandardError
      attr_reader :details

      def initialize(details)
        super
        @details = details
      end
    end

    class Contract
      SCHEMA_VERSION = 1
      ROOT_FIELDS = %w[ci_policy execution_policy platform schema_version validations].freeze
      VALIDATION_FIELDS = %w[
        command id label owned_directories pass_marker profile timeout_seconds trusted_artifacts
      ].freeze
      EXPECTED_ORDER = %w[address-sanitizer undefined-behavior-sanitizer].freeze
      EXPECTED_TIMEOUT_SECONDS = 600
      EXPECTED_LABELS = {
        'address-sanitizer' => 'AddressSanitizer',
        'undefined-behavior-sanitizer' => 'UndefinedBehaviorSanitizer',
      }.freeze
      EXPECTED_ARTIFACTS = {
        'address-sanitizer' => AddressSanitizerGate::SUPPORTED_TRUSTED_ARTIFACTS,
        'undefined-behavior-sanitizer' =>
          UndefinedBehaviorSanitizerGate::SUPPORTED_TRUSTED_ARTIFACTS,
      }.freeze

      attr_reader :data

      def self.load(path)
        new(JSON.parse(File.binread(path)))
      end

      def initialize(data)
        @data = data
      end

      def platform
        data.fetch('platform')
      end

      def validations
        data.fetch('validations')
      end

      def validate!(root:, toolchain:)
        errors = shape_errors
        errors.concat(linkage_errors(root, toolchain)) if errors.empty?
        raise ContractFailure.new(errors.sort.join('; ')) unless errors.empty?

        self
      end

    private

      def shape_errors
        return ['document root must be an object'] unless data.is_a?(Hash)

        errors = []
        errors << "schema_version must be #{SCHEMA_VERSION}" unless data['schema_version'] == SCHEMA_VERSION
        errors << "root fields must be exactly #{ROOT_FIELDS.join(', ')}" unless data.keys.sort == ROOT_FIELDS
        errors << 'platform must be linux-x86_64' unless data['platform'] == 'linux-x86_64'
        errors << 'execution_policy must be fail-fast' unless data['execution_policy'] == 'fail-fast'
        unless data['ci_policy'] == 'independent-blocking-jobs'
          errors << 'ci_policy must be independent-blocking-jobs'
        end

        entries = data['validations']
        unless entries.is_a?(Array)
          errors << 'validations must be an array'
          return errors
        end
        ids = entries.filter_map { |entry| entry['id'] if entry.is_a?(Hash) }
        errors << "validation order must be #{EXPECTED_ORDER.join(' then ')}" unless ids == EXPECTED_ORDER
        entries.each_with_index do |validation, index|
          errors.concat(validation_shape_errors(validation, index))
        end
        errors
      end

      def validation_shape_errors(validation, index)
        location = "validations[#{index}]"
        return ["#{location} must be an object"] unless validation.is_a?(Hash)

        errors = []
        errors << "#{location} fields must be exactly #{VALIDATION_FIELDS.join(', ')}" \
          unless validation.keys.sort == VALIDATION_FIELDS
        %w[id label pass_marker profile].each do |field|
          value = validation[field]
          errors << "#{location}.#{field} must be a non-empty string" \
            unless value.is_a?(String) && !value.empty?
        end
        %w[command owned_directories trusted_artifacts].each do |field|
          value = validation[field]
          valid = value.is_a?(Array) && !value.empty? &&
                  value.all? { |part| part.is_a?(String) && !part.empty? }
          errors << "#{location}.#{field} must be a non-empty string array" unless valid
        end
        timeout = validation['timeout_seconds']
        if !timeout.is_a?(Integer) || !timeout.positive?
          errors << "#{location}.timeout_seconds must be a positive integer"
        elsif timeout != EXPECTED_TIMEOUT_SECONDS
          errors << "#{location}.timeout_seconds must remain #{EXPECTED_TIMEOUT_SECONDS}"
        end
        errors
      end

      def linkage_errors(root, toolchain)
        return ['config/supported_toolchain.json does not match its current schema'] \
          unless toolchain.valid_structure?

        errors = []
        validations.each do |validation|
          id = validation.fetch('id')
          profile = toolchain.profiles.fetch(validation.fetch('profile'), nil)
          unless profile
            errors << "#{id} profile is missing from config/supported_toolchain.json"
            next
          end
          errors.concat(profile_linkage_errors(root, validation, profile))
        end
        errors.concat(repository_linkage_errors(root))
        errors
      end

      def profile_linkage_errors(root, validation, profile)
        id = validation.fetch('id')
        errors = []
        expected_label = EXPECTED_LABELS.fetch(id)
        errors << "#{id} label must remain #{expected_label}" unless validation['label'] == expected_label
        errors << "#{id} platform must match #{platform}" unless profile['platform'] == platform
        expected_command = profile.fetch('ci').fetch('command').split
        errors << "#{id} command must match its independent gate" unless validation['command'] == expected_command
        expected_directories = [profile['build_directory'], profile['binary_directory']]
        unless validation['owned_directories'] == expected_directories
          errors << "#{id} owned directories must match its independent gate"
        end
        expected_artifacts = EXPECTED_ARTIFACTS.fetch(id)
        unless validation['trusted_artifacts'] == expected_artifacts
          errors << "#{id} trusted artifacts drifted from its independent gate"
        end
        target_artifacts = validation['trusted_artifacts'].grep(/\Anative-target:/).map do |item|
          item.split(':', 2).last
        end
        unless target_artifacts == profile.fetch('targets').keys
          errors << "#{id} native target order or membership drifted from its profile"
        end
        validation['trusted_artifacts'].grep(/\Asource:/).each do |artifact|
          relative_path = artifact.split(':', 2).last
          unless File.file?(File.join(root, relative_path))
            errors << "#{id} trusted source is missing: #{relative_path}"
          end
        end
        expected_marker = "#{expected_label} gate: PASSED"
        unless validation['pass_marker'] == expected_marker
          errors << "#{id} pass marker must remain #{expected_marker}"
        end
        errors
      end

      def repository_linkage_errors(root)
        errors = []
        manifest = JSON.parse(File.binread(File.join(root, 'config/test_suites.json')))
        workflow = YAML.safe_load(
          File.binread(File.join(root, '.github/workflows/ruby.yml')),
          aliases: false
        )
        suites_by_id = manifest.fetch('suites').group_by do |suite|
          suite.fetch('id')
        end
        suites_by_id.select { |_id, suites| suites.length > 1 }.keys.sort.each do |id|
          errors << "test-suite manifest contains duplicate suite id: #{id}"
        end
        expected_suite_commands = {
          'rake-address-sanitizer' => %w[bundle exec rake address_sanitizer_spec],
          'rake-undefined-behavior-sanitizer' =>
            %w[bundle exec rake undefined_behavior_sanitizer_spec],
          'rake-combined-sanitizer' => %w[bundle exec rake combined_sanitizer_spec],
        }
        expected_suite_commands.each do |id, command|
          suites = suites_by_id.fetch(id, [])
          if suites.empty?
            errors << "test-suite manifest is missing required suite id: #{id}"
            next
          end
          next unless suites.one?

          errors << "test-suite manifest command drifted for #{id}" unless suites.first['command'] == command
        end

        workflow_runs = workflow.fetch('jobs').values.flat_map do |job|
          job.fetch('steps').filter_map { |step| step['run'] }
        end
        validations.each do |validation|
          command = validation.fetch('command').join(' ')
          count = workflow_runs.count(command)
          unless count == 1
            errors << "CI must invoke #{validation.fetch('label')} exactly once, got #{count}"
          end
        end
        combined_command = 'bundle exec rake combined_sanitizer_spec'
        if workflow_runs.include?(combined_command)
          errors << 'CI must contract-check the combined gate without rerunning both sanitizer jobs'
        end
        errors
      rescue Errno::ENOENT => e
        ["repository contract file is missing: #{e.message}"]
      rescue JSON::ParserError, Psych::Exception => e
        ["repository contract cannot be parsed: #{e.class}: #{e.message}"]
      rescue KeyError, NoMethodError, TypeError => e
        ["repository contract has invalid structure: #{e.class}: #{e.message}"]
      end
    end

    class Runner
      CONTRACT_PATH = 'config/combined_sanitizer_gate.json'.freeze

      def initialize(root:, executor: UndefinedBehaviorSanitizerGate::SystemExecutor.new,
                     output: $stdout, error: $stderr,
                     host_os: RbConfig::CONFIG['host_os'],
                     host_cpu: RbConfig::CONFIG['host_cpu'])
        @root = File.expand_path(root)
        @executor = executor
        @output = output
        @error = error
        @host_os = ToolchainPreflight::Platform.os(host_os)
        @host_cpu = ToolchainPreflight::Platform.architecture(host_cpu)
      end

      def run
        contract = load_contract
        validate_host(contract)
        contract.validations.each_with_index do |validation, index|
          result = run_validation(validation)
          next if complete?(validation, result)

          report_failure(validation, result, contract.validations.drop(index + 1))
          return failure_status(result.exit_code)
        end
        announce(
          @output,
          'Combined sanitizer gate: PASSED (AddressSanitizer then UndefinedBehaviorSanitizer)'
        )
        0
      rescue ContractFailure => e
        announce(@error, "Combined sanitizer gate: FAILED during contract validation: #{e.details}")
        1
      rescue Errno::ENOENT, Errno::EACCES, IOError, JSON::ParserError, KeyError, TypeError => e
        announce(@error, "Combined sanitizer gate: FAILED during setup: #{e.class}: #{e.message}")
        1
      end

    private

      def load_contract
        toolchain = ToolchainPreflight::Contract.load(
          File.join(@root, 'config/supported_toolchain.json')
        )
        Contract.load(File.join(@root, CONTRACT_PATH)).validate!(root: @root, toolchain: toolchain)
      end

      def validate_host(contract)
        actual = "#{@host_os}-#{@host_cpu}"
        return if actual == contract.platform

        raise ContractFailure.new("supported #{contract.platform}; current #{actual}")
      end

      def run_validation(validation)
        label = validation.fetch('label')
        announce(@output, "Combined sanitizer gate: START #{label}")
        result = @executor.call(
          validation.fetch('command'),
          chdir: @root,
          timeout: validation.fetch('timeout_seconds')
        )
        @output.print(result.stdout) unless result.stdout.empty?
        @error.print(result.stderr) unless result.stderr.empty?
        result
      end

      def complete?(validation, result)
        result.success? && result.stdout.lines.map(&:chomp).include?(validation.fetch('pass_marker'))
      end

      def report_failure(validation, result, remaining)
        label = validation.fetch('label')
        reason = if result.timed_out
                   "timed out after #{validation.fetch('timeout_seconds')} seconds"
                 elsif result.success?
                   "exited successfully without #{validation.fetch('pass_marker').dump}"
                 else
                   'returned nonzero'
                 end
        announce(@error, "Combined sanitizer gate: FAILED in #{label} (#{reason})")
        announce(@error, "command: #{validation.fetch('command').join(' ')}")
        announce(@error, "exit status: #{failure_status(result.exit_code)}")
        remaining.each do |pending|
          announce(@error, "#{pending.fetch('label')}: NOT RUN (fail-fast after #{label})")
        end
      end

      def failure_status(status)
        status.nil? || status.zero? ? 1 : status
      end

      def announce(stream, message)
        stream.puts(message)
        stream.flush
      end
    end
  end
end
