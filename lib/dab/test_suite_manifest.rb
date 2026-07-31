require 'json'
require 'pathname'
require 'rake'
require 'stringio'

require_relative 'complete_gate'

module Dab
  module TestSuiteManifest
    SCHEMA_VERSION = 1
    STATES = %w[active pending disabled].freeze
    SUITE_KINDS = %w[rake command].freeze
    EVIDENCE_TYPES = %w[pattern excluded_from_task].freeze
    ROOT_FIELDS = %w[schema_version suites exceptions].freeze
    SUITE_FIELDS = %w[id state kind command rake_task source_glob in_complete_gate reason].freeze
    EXCEPTION_FIELDS = %w[id state source_glob evidence reason].freeze
    EVIDENCE_FIELDS = %w[type value].freeze
    ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/.freeze

    Result = Struct.new(:errors, :suite_count, :exception_count) do
      def success?
        errors.empty?
      end
    end

    class Topology
      attr_reader :fixture_tasks, :gate_fixture_tasks, :suite_commands

      def initialize(root:)
        @root = root
        @application = load_rakefile
        @fixture_tasks = discover_fixture_tasks
        @gate_fixture_tasks = fixture_tasks.select { |name| reachable?('default', name) }.sort
        @suite_commands = discover_suite_commands
      end

      def task?(name)
        !@application.lookup(name).nil?
      end

      def fixture_task_for(name)
        return name if fixture_tasks.include?(name)
        return unless task?(name)

        matches = fixture_tasks.select { |fixture_task| reachable?(name, fixture_task) }
        matches.one? ? matches.first : nil
      end

      def task_inputs(name)
        return [] unless task?(name)

        reachable_names(name).select do |path|
          File.file?(File.join(@root, path))
        end.map { |path| Pathname.new(path).cleanpath.to_s.tr('\\', '/') }.sort
      end

    private

      def load_rakefile
        application = Rake::Application.new
        previous_application = Rake.application
        previous_directory = Dir.pwd
        previous_stdout = $stdout
        previous_stderr = $stderr
        parallel_environment = ENV.to_h.slice('CI_PARALLEL_INDEX', 'CI_PARALLEL_TOTAL')

        begin
          ENV.delete('CI_PARALLEL_INDEX')
          ENV.delete('CI_PARALLEL_TOTAL')
          Rake.application = application
          Dir.chdir(@root)
          $stdout = StringIO.new
          $stderr = StringIO.new
          application.init
          application.load_rakefile
        ensure
          parallel_environment.each { |name, value| ENV[name] = value }
          Rake.application = previous_application
          Dir.chdir(previous_directory)
          $stdout = previous_stdout
          $stderr = previous_stderr
        end

        application
      end

      def discover_fixture_tasks
        @application.tasks.filter_map do |task|
          next if task.name.end_with?('_reverse')

          task.name if @application.lookup("#{task.name}_reverse")
        end.sort
      end

      def discover_suite_commands
        runner = Dab::CompleteGate::Runner
        administrative = [
          runner::MANIFEST_COMMAND,
          runner::PREFLIGHT_COMMAND,
          runner::INHERITED_GATE_COMMAND,
        ]
        runner::STAGES.map(&:last).reject { |command| administrative.include?(command) }
      end

      def reachable?(from, target)
        reachable_names(from).include?(target)
      end

      def reachable_names(name, seen = {})
        return [] if seen[name]

        seen[name] = true
        task = @application.lookup(name)
        return [] unless task

        task.prerequisites.flat_map do |prerequisite|
          [prerequisite, *reachable_names(prerequisite, seen)]
        end.uniq
      end
    end

    class Validator
      def initialize(root:)
        @root = File.expand_path(root)
      end

      def validate(path: File.join(@root, 'config/test_suites.json'))
        @errors = []
        document = parse(path)
        return result unless document

        validate_root(document)
        return result unless @errors.empty?

        suites = document.fetch('suites')
        exceptions = document.fetch('exceptions')
        validate_ids(suites, exceptions)
        suites.each_with_index { |suite, index| validate_suite_shape(suite, index) }
        exceptions.each_with_index { |exception, index| validate_exception_shape(exception, index) }
        return result(suites, exceptions) unless @errors.empty?

        topology = Topology.new(root: @root)
        validate_suites(suites, topology)
        validate_exceptions(exceptions, topology)
        result(suites, exceptions)
      rescue StandardError => e
        @errors << "topology inspection failed: #{e.class}: #{e.message}"
        result
      end

    private

      def parse(path)
        JSON.parse(File.binread(path))
      rescue Errno::ENOENT
        @errors << "manifest file does not exist: #{portable_path(path)}"
        nil
      rescue Errno::EACCES
        @errors << "manifest file is not readable: #{portable_path(path)}"
        nil
      rescue JSON::ParserError => e
        @errors << "manifest is malformed JSON: #{e.message}"
        nil
      end

      def validate_root(document)
        unless document.is_a?(Hash)
          @errors << "root must be an object, got #{type_name(document)}"
          return
        end

        validate_fields(document, ROOT_FIELDS, 'root')
        schema_version = document['schema_version']
        if schema_version != SCHEMA_VERSION
          @errors << "schema_version must be #{SCHEMA_VERSION}, got #{schema_version.inspect}"
        end
        @errors << "suites must be an array, got #{type_name(document['suites'])}" unless document['suites'].is_a?(Array)
        unless document['exceptions'].is_a?(Array)
          @errors << "exceptions must be an array, got #{type_name(document['exceptions'])}"
        end
      end

      def validate_ids(suites, exceptions)
        entries = suites.map.with_index { |entry, index| [entry, "suites[#{index}]"] }
        entries += exceptions.map.with_index { |entry, index| [entry, "exceptions[#{index}]"] }
        ids = Hash.new { |hash, key| hash[key] = [] }

        entries.each do |entry, location|
          next unless entry.is_a?(Hash)

          id = entry['id']
          if !id.is_a?(String) || !id.match?(ID_PATTERN)
            @errors << "#{location}.id must be a stable kebab-case string"
          else
            ids[id] << location
          end
        end

        ids.each do |id, locations|
          @errors << "duplicate id #{id.inspect} at #{locations.join(', ')}" if locations.length > 1
        end
      end

      def validate_suite_shape(suite, index)
        location = "suites[#{index}]"
        unless suite.is_a?(Hash)
          @errors << "#{location} must be an object, got #{type_name(suite)}"
          return
        end

        validate_fields(suite, SUITE_FIELDS, location)
        validate_state(suite, location)
        validate_nonempty_string(suite, 'kind', location)
        unless SUITE_KINDS.include?(suite['kind'])
          @errors << "#{location}.kind must be one of #{SUITE_KINDS.join(', ')}"
        end
        validate_command(suite['command'], location)
        validate_nonempty_string(suite, 'source_glob', location)
        unless [true, false].include?(suite['in_complete_gate'])
          @errors << "#{location}.in_complete_gate must be a boolean"
        end
        validate_reason(suite, location)

        if suite['kind'] == 'rake'
          validate_nonempty_string(suite, 'rake_task', location)
        elsif suite.key?('rake_task')
          @errors << "#{location}.rake_task is only valid for kind rake"
        end
      end

      def validate_exception_shape(exception, index)
        location = "exceptions[#{index}]"
        unless exception.is_a?(Hash)
          @errors << "#{location} must be an object, got #{type_name(exception)}"
          return
        end

        validate_fields(exception, EXCEPTION_FIELDS, location)
        validate_state(exception, location)
        if exception['state'] == 'active'
          @errors << "#{location}.state must be pending or disabled for an exception"
        end
        validate_nonempty_string(exception, 'source_glob', location)
        validate_nonempty_string(exception, 'reason', location)
        validate_evidence(exception['evidence'], location)
      end

      def validate_state(entry, location)
        state = entry['state']
        return if STATES.include?(state)

        @errors << "#{location}.state must be one of #{STATES.join(', ')}"
      end

      def validate_command(command, location)
        unless command.is_a?(Array) && !command.empty? && command.all? { |part| part.is_a?(String) && !part.empty? }
          @errors << "#{location}.command must be a non-empty array of non-empty strings"
        end
      end

      def validate_reason(entry, location)
        return if entry['state'] == 'active'

        validate_nonempty_string(entry, 'reason', location)
      end

      def validate_evidence(evidence, location)
        unless evidence.is_a?(Hash)
          @errors << "#{location}.evidence must be an object, got #{type_name(evidence)}"
          return
        end

        validate_fields(evidence, EVIDENCE_FIELDS, "#{location}.evidence")
        unless EVIDENCE_TYPES.include?(evidence['type'])
          @errors << "#{location}.evidence.type must be one of #{EVIDENCE_TYPES.join(', ')}"
        end
        validate_nonempty_string(evidence, 'value', "#{location}.evidence")
      end

      def validate_nonempty_string(entry, field, location)
        value = entry[field]
        return if value.is_a?(String) && !value.empty?

        @errors << "#{location}.#{field} must be a non-empty string"
      end

      def validate_fields(entry, allowed, location)
        unknown = entry.keys - allowed
        missing = allowed.select { |field| required_field?(field, location) && !entry.key?(field) }
        @errors << "#{location} has unsupported fields: #{unknown.sort.join(', ')}" unless unknown.empty?
        @errors << "#{location} is missing fields: #{missing.sort.join(', ')}" unless missing.empty?
      end

      def required_field?(field, location)
        return false if %w[reason rake_task].include?(field)

        location != 'root' || ROOT_FIELDS.include?(field)
      end

      def validate_suites(suites, topology)
        rake_suites = suites.select { |suite| suite['kind'] == 'rake' }
        command_suites = suites.select { |suite| suite['kind'] == 'command' }
        resolved_tasks = {}

        rake_suites.each do |suite|
          validate_source_glob(suite['source_glob'], suite['id'])
          task = suite['rake_task']
          unless topology.task?(task)
            @errors << "suite #{suite['id']}: Rake task #{task.inspect} does not exist"
            next
          end

          fixture_task = topology.fixture_task_for(task)
          unless fixture_task
            @errors << "suite #{suite['id']}: Rake task #{task.inspect} does not resolve to exactly one fixture suite"
            next
          end

          if resolved_tasks.key?(fixture_task)
            @errors << "fixture suite #{fixture_task.inspect} is represented by both #{resolved_tasks[fixture_task]} and #{suite['id']}"
          else
            resolved_tasks[fixture_task] = suite['id']
          end

          expected_command = %w[bundle exec rake] + [task]
          if suite['command'] != expected_command
            @errors << "suite #{suite['id']}: command must be #{expected_command.inspect} for Rake task #{task.inspect}"
          end
          validate_glob_wiring(suite, topology, task)
          actual_gate = topology.gate_fixture_tasks.include?(fixture_task)
          validate_gate_membership(suite, actual_gate)
        end

        missing_tasks = topology.fixture_tasks - resolved_tasks.keys
        extra_tasks = resolved_tasks.keys - topology.fixture_tasks
        @errors << "manifest is missing Rake fixture suites: #{missing_tasks.join(', ')}" unless missing_tasks.empty?
        @errors << "manifest has unknown Rake fixture suites: #{extra_tasks.join(', ')}" unless extra_tasks.empty?

        validate_command_suites(command_suites, topology)
      end

      def validate_command_suites(suites, topology)
        commands = Hash.new { |hash, key| hash[key] = [] }
        suites.each do |suite|
          validate_source_glob(suite['source_glob'], suite['id'])
          commands[suite['command']] << suite['id']
          validate_gate_membership(suite, topology.suite_commands.include?(suite['command']))
        end

        commands.each do |command, ids|
          @errors << "command suite #{command.inspect} is represented more than once: #{ids.join(', ')}" if ids.length > 1
        end
        missing = topology.suite_commands - commands.keys
        extra = commands.keys - topology.suite_commands
        @errors << "manifest is missing complete-gate command suites: #{missing.map(&:inspect).join(', ')}" unless missing.empty?
        @errors << "manifest has unwired command suites: #{extra.map(&:inspect).join(', ')}" unless extra.empty?
      end

      def validate_glob_wiring(suite, topology, task)
        files = glob_files(suite['source_glob'])
        inputs = topology.task_inputs(task)
        missing = files - inputs
        return if missing.empty?

        @errors << "suite #{suite['id']}: source_glob includes files not wired to #{task}: #{missing.join(', ')}"
      end

      def validate_gate_membership(suite, actual)
        return if suite['in_complete_gate'] == actual

        @errors << "suite #{suite['id']}: in_complete_gate is #{suite['in_complete_gate'].inspect}, but current wiring is #{actual}"
      end

      def validate_exceptions(exceptions, topology)
        exceptions.each do |exception|
          files = validate_source_glob(exception['source_glob'], exception['id'])
          next if files.empty?

          evidence = exception['evidence']
          case evidence['type']
          when 'pattern'
            validate_pattern_evidence(exception, files, evidence['value'])
          when 'excluded_from_task'
            validate_excluded_evidence(exception, files, topology, evidence['value'])
          end
        end
      end

      def validate_pattern_evidence(exception, files, pattern_source)
        pattern = Regexp.new(pattern_source)
        return if files.any? { |path| File.binread(File.join(@root, path)).match?(pattern) }

        @errors << "exception #{exception['id']}: evidence pattern #{pattern_source.inspect} matches none of its source files"
      rescue RegexpError => e
        @errors << "exception #{exception['id']}: evidence pattern is invalid: #{e.message}"
      end

      def validate_excluded_evidence(exception, files, topology, task)
        unless topology.task?(task)
          @errors << "exception #{exception['id']}: evidence Rake task #{task.inspect} does not exist"
          return
        end

        included = files & topology.task_inputs(task)
        return if included.empty?

        @errors << "exception #{exception['id']}: files are now wired to #{task}: #{included.join(', ')}"
      end

      def validate_source_glob(glob, id)
        return [] unless portable_glob?(glob)

        files = glob_files(glob)
        @errors << "entry #{id}: source_glob matches no files: #{glob}" if files.empty?
        files
      end

      def portable_glob?(glob)
        return false unless glob.is_a?(String)

        path = Pathname.new(glob)
        if path.absolute? || glob.include?('\\') || path.each_filename.include?('..')
          @errors << "source_glob must be a portable repository-relative path: #{glob.inspect}"
          return false
        end
        true
      end

      def glob_files(glob)
        Dir.glob(File.join(@root, glob)).select { |path| File.file?(path) }.map do |path|
          portable_path(path.delete_prefix("#{@root}/"))
        end.sort
      end

      def portable_path(path)
        path.to_s.tr('\\', '/')
      end

      def type_name(value)
        value.nil? ? 'null' : value.class.name
      end

      def result(suites = [], exceptions = [])
        Result.new(@errors.uniq.sort, suites.length, exceptions.length)
      end
    end
  end
end
