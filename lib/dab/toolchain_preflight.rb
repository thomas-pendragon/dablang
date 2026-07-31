require 'json'
require 'open3'
require 'rbconfig'
require 'yaml'

module Dab
  module ToolchainPreflight
    CommandResult = Struct.new(:command, :path, :stdout, :stderr, :success)
    RunResult = Struct.new(:success, :output, :errors) do
      def success?
        success
      end
    end

    class Contract
      SCHEMA_VERSION = 3
      TOP_LEVEL_STRINGS = %w[default_ruby_version bundler_version premake_version premake_action].freeze
      PLATFORM_STRINGS = %w[os architecture premake_command build_driver compiler clang_format].freeze
      CI_STRINGS = %w[job runner ruby_setup premake_command premake_asset].freeze
      ADDRESS_SANITIZER_STRINGS = %w[
        platform compiler compiler_version c_compiler configuration premake_option
        build_directory object_directory binary_directory metadata_tool instrumentation_symbol
      ].freeze
      ADDRESS_SANITIZER_ARRAYS = %w[compile_flags link_flags].freeze
      ADDRESS_SANITIZER_CI_STRINGS = %w[
        job runner ruby_setup premake_command premake_asset command compiler_setup
      ].freeze
      TOP_LEVEL_FIELDS = (%w[schema_version platforms profiles] + TOP_LEVEL_STRINGS).freeze
      PLATFORM_FIELDS = (%w[ruby_versions ci] + PLATFORM_STRINGS).freeze
      ADDRESS_SANITIZER_FIELDS = (
        %w[leak_detection targets ci] + ADDRESS_SANITIZER_STRINGS + ADDRESS_SANITIZER_ARRAYS
      ).freeze
      UNDEFINED_BEHAVIOR_SANITIZER_STRINGS = %w[
        platform compiler compiler_version c_compiler configuration premake_option
        build_directory object_directory binary_directory metadata_tool instrumentation_symbol
        symbolizer_tool
      ].freeze
      UNDEFINED_BEHAVIOR_SANITIZER_ARRAYS = %w[compile_flags link_flags].freeze
      UNDEFINED_BEHAVIOR_SANITIZER_CI_STRINGS = ADDRESS_SANITIZER_CI_STRINGS
      UNDEFINED_BEHAVIOR_SANITIZER_FIELDS = (
        %w[targets ci] + UNDEFINED_BEHAVIOR_SANITIZER_STRINGS + UNDEFINED_BEHAVIOR_SANITIZER_ARRAYS
      ).freeze

      attr_reader :data

      def self.load(path)
        new(JSON.parse(File.read(path)))
      end

      def initialize(data)
        @data = data
      end

      def default_ruby_version
        data.fetch('default_ruby_version')
      end

      def bundler_version
        data.fetch('bundler_version')
      end

      def premake_version
        data.fetch('premake_version')
      end

      def premake_action
        data.fetch('premake_action')
      end

      def platforms
        data.fetch('platforms')
      end

      def profiles
        data.fetch('profiles')
      end

      def address_sanitizer
        profiles.fetch('address_sanitizer')
      end

      def undefined_behavior_sanitizer
        profiles.fetch('undefined_behavior_sanitizer')
      end

      def platform(os, architecture)
        platforms.values.find do |candidate|
          candidate.fetch('os') == os && candidate.fetch('architecture') == architecture
        end
      end

      def valid_structure?
        return false unless data.is_a?(Hash) && data['schema_version'] == SCHEMA_VERSION
        return false unless data.keys.sort == TOP_LEVEL_FIELDS.sort
        return false unless TOP_LEVEL_STRINGS.all? { |key| data[key].is_a?(String) }

        supported_platforms = data['platforms']
        return false unless supported_platforms.is_a?(Hash) && !supported_platforms.empty?

        return false unless supported_platforms.all? { |name, candidate| name.is_a?(String) && valid_platform?(candidate) }

        profiles = data['profiles']
        expected_profiles = %w[address_sanitizer undefined_behavior_sanitizer]
        return false unless profiles.is_a?(Hash) && profiles.keys.sort == expected_profiles

        valid_address_sanitizer?(profiles['address_sanitizer']) &&
          valid_undefined_behavior_sanitizer?(profiles['undefined_behavior_sanitizer'])
      end

    private

      def valid_platform?(candidate)
        return false unless candidate.is_a?(Hash)
        return false unless candidate.keys.sort == PLATFORM_FIELDS.sort
        return false unless PLATFORM_STRINGS.all? { |key| candidate[key].is_a?(String) }

        ruby_versions = candidate['ruby_versions']
        return false unless ruby_versions.is_a?(Array) && !ruby_versions.empty?
        return false unless ruby_versions.all? { |version| version.is_a?(String) }

        ci = candidate['ci']
        allowed_ci_fields = CI_STRINGS + ['clang_format']
        ci.is_a?(Hash) && (ci.keys - allowed_ci_fields).empty? && CI_STRINGS.all? { |key| ci[key].is_a?(String) } &&
          (!ci.key?('clang_format') || ci['clang_format'].is_a?(String))
      end

      def valid_address_sanitizer?(profile)
        return false unless profile.is_a?(Hash)
        return false unless profile.keys.sort == ADDRESS_SANITIZER_FIELDS.sort
        return false unless ADDRESS_SANITIZER_STRINGS.all? { |key| profile[key].is_a?(String) }
        return false unless ADDRESS_SANITIZER_ARRAYS.all? do |key|
          profile[key].is_a?(Array) && !profile[key].empty? && profile[key].all? { |value| value.is_a?(String) }
        end
        return false unless profile['leak_detection'] == true

        targets = profile['targets']
        expected_targets = %w[cdisasm cdumpcov cffitest cvm]
        return false unless targets.is_a?(Hash) && targets.keys.sort == expected_targets
        return false unless targets.values.all? { |value| value.is_a?(String) && !value.empty? }

        ci = profile['ci']
        ci.is_a?(Hash) && ci.keys.sort == ADDRESS_SANITIZER_CI_STRINGS.sort &&
          ADDRESS_SANITIZER_CI_STRINGS.all? { |key| ci[key].is_a?(String) }
      end

      def valid_undefined_behavior_sanitizer?(profile)
        return false unless profile.is_a?(Hash)
        return false unless profile.keys.sort == UNDEFINED_BEHAVIOR_SANITIZER_FIELDS.sort
        return false unless UNDEFINED_BEHAVIOR_SANITIZER_STRINGS.all? { |key| profile[key].is_a?(String) }
        return false unless UNDEFINED_BEHAVIOR_SANITIZER_ARRAYS.all? do |key|
          profile[key].is_a?(Array) && !profile[key].empty? && profile[key].all? { |value| value.is_a?(String) }
        end

        targets = profile['targets']
        expected_targets = %w[cdisasm cdumpcov cffitest cvm]
        return false unless targets.is_a?(Hash) && targets.keys.sort == expected_targets
        return false unless targets.values.all? { |value| value.is_a?(String) && !value.empty? }

        ci = profile['ci']
        ci.is_a?(Hash) && ci.keys.sort == UNDEFINED_BEHAVIOR_SANITIZER_CI_STRINGS.sort &&
          UNDEFINED_BEHAVIOR_SANITIZER_CI_STRINGS.all? { |key| ci[key].is_a?(String) }
      end
    end

    class Platform
      def self.os(host_os)
        case host_os
        when /linux/i
          'linux'
        when /darwin/i
          'macos'
        when /mswin|mingw|cygwin/i
          'windows'
        else
          host_os
        end
      end

      def self.architecture(host_cpu)
        case host_cpu
        when /x86_64|amd64|x64/i
          'x86_64'
        when /aarch64|arm64/i
          'arm64'
        else
          host_cpu
        end
      end
    end

    class SystemProbe
      def initialize(root:, environment: ENV)
        @root = root
        @environment = environment
      end

      def capture(command, *arguments)
        path = resolve(command)
        return CommandResult.new(command, nil, '', '', false) unless path

        stdout, stderr, status = Open3.capture3(path, *arguments, chdir: @root)
        CommandResult.new(command, path, stdout, stderr, status.success?)
      rescue SystemCallError => e
        CommandResult.new(command, path, '', e.message, false)
      end

    private

      def resolve(command)
        return nil if command.nil? || command.strip.empty?

        if command[/[\\\/]/]
          path = File.expand_path(command, @root)
          return path if File.file?(path)

          return nil
        end

        executable_names(command).each do |name|
          path_entries.each do |directory|
            path = File.join(directory, name)
            return path if File.file?(path) && File.executable?(path)
          end
        end
        nil
      end

      def path_entries
        @environment.fetch('PATH', '').split(File::PATH_SEPARATOR)
      end

      def executable_names(command)
        return [command] unless Gem.win_platform?
        return [command] unless File.extname(command).empty?

        extensions = @environment.fetch('PATHEXT', '.COM;.EXE;.BAT;.CMD').split(';')
        [command] + extensions.map { |extension| "#{command}#{extension.downcase}" }
      end
    end

    class RepositoryContract
      WORKFLOW_PATH = '.github/workflows/ruby.yml'.freeze
      COMPLETE_GATE_COMMAND = 'ruby script/complete_gate.rb'.freeze

      def initialize(root:, contract:)
        @root = root
        @contract = contract
      end

      def errors
        result = []
        safely_check(result, '.ruby-version') { check_ruby_version(result) }
        safely_check(result, 'Gemfile.lock') { check_bundler_version(result) }
        safely_check(result, 'Rakefile') { check_rakefile(result) }
        safely_check(result, WORKFLOW_PATH) { check_workflow(result) }
        result
      end

    private

      def safely_check(errors, relative_path)
        yield
      rescue Errno::ENOENT
        errors << "#{relative_path} is missing; restore it from the repository"
      rescue SystemCallError, IOError
        errors << "#{relative_path} is unreadable; repair its permissions"
      rescue Psych::SyntaxError
        errors << "#{relative_path} is invalid YAML; fix its syntax"
      rescue Psych::Exception
        errors << "#{relative_path} cannot be loaded safely as YAML; remove aliases or unsupported YAML constructs"
      rescue KeyError, NoMethodError, TypeError
        errors << "#{relative_path} does not match the supported-toolchain structure"
      end

      def check_ruby_version(errors)
        actual = read('.ruby-version').strip
        expected = @contract.default_ruby_version
        return if actual == expected

        errors << ".ruby-version is #{actual.inspect}; set it to the supported default #{expected}"
      end

      def check_bundler_version(errors)
        lockfile = read('Gemfile.lock')
        actual = lockfile[/^BUNDLED WITH\s*\n\s+(\S+)\s*$/, 1]
        expected = @contract.bundler_version
        return if actual == expected

        errors << "Gemfile.lock records Bundler #{actual || 'unknown'}; regenerate it with Bundler #{expected}"
      end

      def check_rakefile(errors)
        rakefile = read('Rakefile')
        expected_action = @contract.premake_action
        unless rakefile.include?("$toolset = ENV['TOOLSET'] || '#{expected_action}'")
          errors << "Rakefile must default TOOLSET to #{expected_action}"
        end

        premake_commands = @contract.platforms.values.map { |platform| platform.fetch('premake_command') }.uniq
        unless premake_commands == ['premake5'] && rakefile.include?("premake = ENV['PREMAKE'] || 'premake5'")
          errors << 'Rakefile PREMAKE selection drifted from the supported-toolchain manifest'
        end

        clang_formats = @contract.platforms.values.map { |platform| platform.fetch('clang_format') }.uniq
        unless clang_formats == ['clang-format'] && rakefile.include?("clang_format_app = ENV['CLANG_FORMAT'] || 'clang-format'")
          errors << 'Rakefile CLANG_FORMAT selection drifted from the supported-toolchain manifest'
        end

        drivers = @contract.platforms.values.map { |platform| platform.fetch('build_driver') }.uniq
        expected_driver_call = "psystem(\"make -f ../\#{makefile} \#{project} verbose=1\")"
        unless drivers == ['make'] && rakefile.include?(expected_driver_call)
          errors << 'Rakefile build driver drifted from the supported-toolchain manifest'
        end
      end

      def check_workflow(errors)
        workflow_text = read(WORKFLOW_PATH)
        workflow = YAML.safe_load(workflow_text, aliases: false)
        structure_error = workflow_structure_error(workflow)
        if structure_error
          errors << "#{WORKFLOW_PATH} has invalid workflow structure: #{structure_error}"
          return
        end

        jobs = workflow.fetch('jobs')

        check_workflow_guards(errors, workflow_text, workflow, jobs)
        @contract.platforms.each_value do |platform|
          check_job(errors, jobs, platform)
        end
        check_address_sanitizer_job(errors, jobs, @contract.address_sanitizer)
        check_undefined_behavior_sanitizer_job(errors, jobs, @contract.undefined_behavior_sanitizer)
      end

      def workflow_structure_error(workflow)
        return 'document root must be a mapping' unless workflow.is_a?(Hash)
        return 'permissions must be a mapping' if workflow.key?('permissions') && !workflow['permissions'].is_a?(Hash)
        return 'concurrency must be a mapping' if workflow.key?('concurrency') && !workflow['concurrency'].is_a?(Hash)

        jobs = workflow['jobs']
        return 'jobs must be a mapping' unless jobs.is_a?(Hash)
        return 'job names must be strings' unless jobs.keys.all? { |name| name.is_a?(String) }

        jobs.each do |name, job|
          error = job_structure_error(name, job)
          return error if error
        end
        nil
      end

      def job_structure_error(name, job)
        return "CI job #{name} must be a mapping" unless job.is_a?(Hash)
        return "CI job #{name} env must be a mapping" if job.key?('env') && !job['env'].is_a?(Hash)

        if job.key?('strategy')
          strategy = job['strategy']
          return "CI job #{name} strategy must be a mapping" unless strategy.is_a?(Hash)
          if strategy.key?('matrix') && !strategy['matrix'].is_a?(Hash)
            return "CI job #{name} strategy matrix must be a mapping"
          end
        end

        steps = job['steps']
        unless steps.is_a?(Array) && steps.all? { |step| step.is_a?(Hash) }
          return "CI job #{name} steps must be a list of mappings"
        end

        invalid_inputs = steps.find { |step| step.key?('with') && !step['with'].is_a?(Hash) }
        return "CI job #{name} step inputs must be mappings" if invalid_inputs

        nil
      end

      def check_workflow_guards(errors, workflow_text, workflow, jobs)
        trigger_block = workflow_text[/^on:\n(?:[ \t].*(?:\n|\z))*/]
        expected_trigger_block = "on:\n  pull_request:\n    branches: [master]\n"
        unless trigger_block == expected_trigger_block
          errors << 'CI trigger drifted; keep the workflow pull-request-only for master'
        end

        permissions = workflow.fetch('permissions', {})
        errors << 'CI permissions drifted; keep contents: read' unless permissions == {'contents' => 'read'}

        concurrency = workflow.fetch('concurrency', {})
        expected_group = 'ci-${{ github.event.pull_request.number }}'
        unless concurrency['group'] == expected_group && concurrency['cancel-in-progress'] == true
          errors << 'CI concurrency drifted; keep per-PR cancellation enabled'
        end

        expected_jobs = @contract.platforms.values.map { |platform| platform.fetch('ci').fetch('job') }
        expected_jobs << @contract.address_sanitizer.fetch('ci').fetch('job')
        expected_jobs << @contract.undefined_behavior_sanitizer.fetch('ci').fetch('job')
        expected_jobs << 'public-site'
        expected_jobs.sort!
        errors << 'CI jobs drifted from the supported-toolchain manifest' unless jobs.keys.sort == expected_jobs
      end

      def check_job(errors, jobs, platform)
        ci = platform.fetch('ci')
        job_name = ci.fetch('job')
        job = jobs[job_name]
        unless job
          errors << "CI job #{job_name} is missing"
          return
        end

        check_job_runner(errors, job_name, job, ci)
        check_job_ruby(errors, job_name, job, platform, ci)
        check_job_tools(errors, job_name, job, ci)
        check_job_steps(errors, job_name, job)
      end

      def check_job_runner(errors, job_name, job, ci)
        return if job['runs-on'] == ci.fetch('runner')

        errors << "CI job #{job_name} must run on #{ci.fetch('runner')}"
      end

      def check_job_ruby(errors, job_name, job, platform, ci)
        if ci.fetch('ruby_setup').include?('matrix.')
          matrix = job.fetch('strategy', {}).fetch('matrix', {}).fetch('ruby-version', [])
          unless matrix == platform.fetch('ruby_versions')
            errors << "CI job #{job_name} Ruby matrix must match the supported-toolchain manifest"
          end
        end

        setup = job.fetch('steps').find { |step| step['uses'] == 'ruby/setup-ruby@v1' }
        actual = setup && setup.fetch('with', {})['ruby-version']
        return if actual == ci.fetch('ruby_setup')

        errors << "CI job #{job_name} Ruby setup must be #{ci.fetch('ruby_setup')}"
      end

      def check_job_tools(errors, job_name, job, ci)
        environment = job.fetch('env', {})
        unless environment['PREMAKE'] == ci.fetch('premake_command')
          errors << "CI job #{job_name} PREMAKE must be #{ci.fetch('premake_command')}"
        end

        steps_text = job.fetch('steps').map { |step| step.fetch('run', '').to_s }.join("\n")
        unless steps_text.include?(ci.fetch('premake_asset')) && steps_text.include?(@contract.premake_version)
          errors << "CI job #{job_name} must install Premake #{@contract.premake_version} from #{ci.fetch('premake_asset')}"
        end

        expected_clang_format = ci['clang_format']
        if expected_clang_format && !steps_text.include?("CLANG_FORMAT=#{expected_clang_format}")
          errors << "CI job #{job_name} must select clang-format at #{expected_clang_format}"
        end
      end

      def check_job_steps(errors, job_name, job)
        steps = job.fetch('steps')
        install_index = steps.index { |step| step['name'] == 'Install Premake' }
        gate_index = steps.index { |step| step['name'] == 'Run complete validation gate' }

        unless install_index && gate_index && install_index < gate_index
          errors << "CI job #{job_name} must run the complete validation gate after Premake installation"
          return
        end

        unless steps[gate_index]['run'] == COMPLETE_GATE_COMMAND
          errors << "CI job #{job_name} must run #{COMPLETE_GATE_COMMAND}"
        end
      end

      def check_address_sanitizer_job(errors, jobs, profile)
        ci = profile.fetch('ci')
        job_name = ci.fetch('job')
        job = jobs[job_name]
        unless job
          errors << "CI job #{job_name} is missing"
          return
        end

        errors << "CI job #{job_name} must run on #{ci.fetch('runner')}" unless job['runs-on'] == ci.fetch('runner')
        errors << "CI job #{job_name} must not use a matrix" if job.key?('strategy')
        if job['continue-on-error']
          errors << "CI job #{job_name} must remain blocking"
        end

        environment = job.fetch('env', {})
        expected_environment = {
          'PREMAKE' => ci.fetch('premake_command'),
          'CC' => profile.fetch('c_compiler'),
          'CXX' => profile.fetch('compiler'),
        }
        unless expected_environment.all? { |key, value| environment[key] == value }
          errors << "CI job #{job_name} compiler and Premake environment must match the AddressSanitizer profile"
        end

        steps = job.fetch('steps')
        if steps.any? { |step| step['continue-on-error'] }
          errors << "CI job #{job_name} steps must remain blocking"
        end
        setup = steps.find { |step| step['uses'] == 'ruby/setup-ruby@v1' }
        actual_ruby = setup && setup.fetch('with', {})['ruby-version']
        unless actual_ruby == ci.fetch('ruby_setup')
          errors << "CI job #{job_name} Ruby setup must be #{ci.fetch('ruby_setup')}"
        end

        steps_text = steps.map { |step| step.fetch('run', '').to_s }.join("\n")
        unless steps_text.include?(ci.fetch('premake_asset')) && steps_text.include?(@contract.premake_version)
          errors << "CI job #{job_name} must install Premake #{@contract.premake_version} from #{ci.fetch('premake_asset')}"
        end
        unless steps_text.include?(ci.fetch('compiler_setup'))
          errors << "CI job #{job_name} must install #{ci.fetch('compiler_setup')}"
        end

        compiler_index = steps.index { |step| step['name'] == 'Install AddressSanitizer compiler' }
        premake_index = steps.index { |step| step['name'] == 'Install Premake' }
        gate_index = steps.index { |step| step['name'] == 'Run AddressSanitizer validation gate' }
        unless compiler_index && premake_index && gate_index && compiler_index < gate_index && premake_index < gate_index
          errors << "CI job #{job_name} must run the AddressSanitizer gate after compiler and Premake installation"
          return
        end
        unless steps[gate_index]['run'] == ci.fetch('command')
          errors << "CI job #{job_name} must run #{ci.fetch('command')}"
        end
      end

      def check_undefined_behavior_sanitizer_job(errors, jobs, profile)
        ci = profile.fetch('ci')
        job_name = ci.fetch('job')
        job = jobs[job_name]
        unless job
          errors << "CI job #{job_name} is missing"
          return
        end

        errors << "CI job #{job_name} must run on #{ci.fetch('runner')}" unless job['runs-on'] == ci.fetch('runner')
        errors << "CI job #{job_name} must not use a matrix" if job.key?('strategy')
        if job['continue-on-error']
          errors << "CI job #{job_name} must remain blocking"
        end

        environment = job.fetch('env', {})
        expected_environment = {
          'PREMAKE' => ci.fetch('premake_command'),
          'CC' => profile.fetch('c_compiler'),
          'CXX' => profile.fetch('compiler'),
        }
        unless expected_environment.all? { |key, value| environment[key] == value }
          errors << "CI job #{job_name} compiler and Premake environment must match the " \
                    'UndefinedBehaviorSanitizer profile'
        end

        steps = job.fetch('steps')
        if steps.any? { |step| step['continue-on-error'] }
          errors << "CI job #{job_name} steps must remain blocking"
        end
        setup = steps.find { |step| step['uses'] == 'ruby/setup-ruby@v1' }
        actual_ruby = setup && setup.fetch('with', {})['ruby-version']
        unless actual_ruby == ci.fetch('ruby_setup')
          errors << "CI job #{job_name} Ruby setup must be #{ci.fetch('ruby_setup')}"
        end

        steps_text = steps.map { |step| step.fetch('run', '').to_s }.join("\n")
        unless steps_text.include?(ci.fetch('premake_asset')) && steps_text.include?(@contract.premake_version)
          errors << "CI job #{job_name} must install Premake #{@contract.premake_version} from #{ci.fetch('premake_asset')}"
        end
        unless steps_text.include?(ci.fetch('compiler_setup'))
          errors << "CI job #{job_name} must install #{ci.fetch('compiler_setup')}"
        end

        compiler_index = steps.index { |step| step['name'] == 'Install UndefinedBehaviorSanitizer compiler' }
        premake_index = steps.index { |step| step['name'] == 'Install Premake' }
        gate_index = steps.index { |step| step['name'] == 'Run UndefinedBehaviorSanitizer validation gate' }
        unless compiler_index && premake_index && gate_index && compiler_index < gate_index && premake_index < gate_index
          errors << "CI job #{job_name} must run the UndefinedBehaviorSanitizer gate after compiler and " \
                    'Premake installation'
          return
        end
        unless steps[gate_index]['run'] == ci.fetch('command')
          errors << "CI job #{job_name} must run #{ci.fetch('command')}"
        end
      end

      def read(relative_path)
        File.read(File.join(@root, relative_path))
      end
    end

    class Runner
      VERSION_ARGUMENTS = ['--version'].freeze

      def initialize(root:, contract: nil, repository_contract: nil, probe: nil, environment: ENV,
                     host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'],
                     ruby_version: RUBY_VERSION, ruby_path: RbConfig.ruby)
        @root = root
        @environment = environment
        @host_os = Platform.os(host_os)
        @host_cpu = Platform.architecture(host_cpu)
        @ruby_version = ruby_version
        @ruby_path = ruby_path
        @contract, @contract_error = load_contract(contract)
        @repository_contract = repository_contract
        if @repository_contract.nil? && @contract
          @repository_contract = RepositoryContract.new(root: root, contract: @contract)
        end
        @probe = probe || SystemProbe.new(root: root, environment: environment)
      end

      def run
        return failure([@contract_error]) if @contract_error

        errors = @repository_contract.errors.dup
        versions = {}
        paths = {}
        platform = @contract.platform(@host_os, @host_cpu)

        unless platform
          errors << "unsupported platform #{@host_os}-#{@host_cpu}; use one of #{supported_platforms.join(', ')}"
        end

        check_ruby(errors, platform)
        probe_exact(errors, versions, paths, 'bundler', 'bundle', @contract.bundler_version, /Bundler version (\S+)/)

        if platform
          check_toolset(errors)
          premake_command = @environment['PREMAKE'] || platform.fetch('premake_command')
          premake_version = @contract.premake_version
          probe_exact(errors, versions, paths, 'premake', premake_command, premake_version, exact_version_pattern(premake_version))
          probe_available(errors, versions, paths, 'driver', platform.fetch('build_driver'))
          probe_available(errors, versions, paths, 'compiler', platform.fetch('compiler'))
          clang_format = @environment['CLANG_FORMAT'] || platform.fetch('clang_format')
          probe_available(errors, versions, paths, 'clang-format', clang_format)
        end

        return failure(errors) unless errors.empty?

        platform_name = "#{@host_os}-#{@host_cpu}"
        fields = [
          "platform=#{platform_name}",
          "ruby=#{@ruby_version}",
          "ruby_path=#{@ruby_path}",
          "bundler=#{versions.fetch('bundler')}",
          "bundler_path=#{paths.fetch('bundler')}",
          "premake=#{versions.fetch('premake')}",
          "premake_path=#{paths.fetch('premake')}",
          "action=#{@contract.premake_action}",
          "driver=#{platform.fetch('build_driver')}@#{versions.fetch('driver')}",
          "driver_path=#{paths.fetch('driver')}",
          "compiler=#{platform.fetch('compiler')}@#{versions.fetch('compiler')}",
          "compiler_path=#{paths.fetch('compiler')}",
          "clang-format=#{platform.fetch('clang_format')}@#{versions.fetch('clang-format')}",
          "clang-format_path=#{paths.fetch('clang-format')}",
        ]
        RunResult.new(true, "supported-toolchain preflight: OK #{fields.join(' ')}\n", [])
      end

    private

      def load_contract(contract)
        return [contract, nil] if contract

        path = File.join(@root, 'config/supported_toolchain.json')
        loaded_contract = Contract.load(path)
        unless loaded_contract.valid_structure?
          return [nil, 'config/supported_toolchain.json does not match the required structure; restore it from the repository']
        end

        [loaded_contract, nil]
      rescue Errno::ENOENT
        [nil, 'config/supported_toolchain.json is missing; restore it from the repository']
      rescue Errno::EACCES, IOError
        [nil, 'config/supported_toolchain.json is unreadable; repair its permissions']
      rescue JSON::ParserError
        [nil, 'config/supported_toolchain.json is invalid JSON; fix its syntax']
      end

      def supported_platforms
        @contract.platforms.keys.sort
      end

      def check_ruby(errors, platform)
        unless platform
          return
        end

        supported = platform.fetch('ruby_versions')
        return if supported.include?(@ruby_version)

        errors << "unsupported Ruby #{@ruby_version} for #{@host_os}-#{@host_cpu}; use #{supported.join(' or ')}"
      end

      def check_toolset(errors)
        selected = @environment['TOOLSET'] || @contract.premake_action
        return if selected == @contract.premake_action

        errors << "unsupported TOOLSET; unset it or use #{@contract.premake_action}"
      end

      def probe_exact(errors, versions, paths, label, command, expected, pattern)
        result = @probe.capture(command, *VERSION_ARGUMENTS)
        unless result.success
          errors << missing_or_failed(label, result)
          return
        end

        actual = result.stdout[pattern, 1] || result.stderr[pattern, 1]
        unless actual
          reported = version_number(result.stdout) || version_number(result.stderr)
          message = if reported
                      "#{label} at #{result.path} is #{reported}; install #{label} #{expected}"
                    else
                      "#{label} at #{result.path} did not report a recognizable version; install #{label} #{expected}"
                    end
          errors << message
          return
        end
        unless actual == expected
          errors << "#{label} at #{result.path} is #{actual}; install #{label} #{expected}"
          return
        end

        versions[label] = actual
        paths[label] = result.path
      end

      def probe_available(errors, versions, paths, label, command)
        result = @probe.capture(command, *VERSION_ARGUMENTS)
        unless result.success
          errors << missing_or_failed(label, result)
          return
        end

        version = version_number(result.stdout) || version_number(result.stderr) || 'available'
        versions[label] = version
        paths[label] = result.path
      end

      def missing_or_failed(label, result)
        if result.path
          "#{label} at #{result.path} could not run --version; repair or replace the selected executable"
        else
          "#{label} executable is missing; install it or select its executable with #{environment_hint(label)}"
        end
      end

      def environment_hint(label)
        case label
        when 'premake'
          'PREMAKE'
        when 'clang-format'
          'CLANG_FORMAT'
        else
          'PATH'
        end
      end

      def version_number(output)
        first_line = output.to_s.lines.first.to_s
        first_line.scan(/\d+(?:\.\d+)+(?:[-+][0-9A-Za-z.-]+)?/).last
      end

      def exact_version_pattern(version)
        /(?<![0-9A-Za-z.+-])(#{Regexp.escape(version)})(?![0-9A-Za-z.+-])/
      end

      def failure(errors)
        lines = ['supported-toolchain preflight: FAILED']
        errors.each { |error| lines << "- #{error}" }
        RunResult.new(false, "#{lines.join("\n")}\n", errors)
      end
    end
  end
end
