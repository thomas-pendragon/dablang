require 'cgi'
require 'fileutils'
require 'open3'
require 'pathname'
require 'tmpdir'
require 'uri'
require 'yaml'

require_relative 'complete_gate'

module Dab::PublicSite
  CLASSIFICATIONS = %w[public_product public_reference repository_only].freeze
  CANONICAL_DOMAIN = 'dablang.net'.freeze
  MANIFEST_PATH = 'docs/_data/public_site.yml'.freeze
  CI_JOB = 'public-site'.freeze
  CI_COMMAND = 'bundle exec ruby script/public_site.rb'.freeze

  Result = Struct.new(:errors, :page_count) do
    def success?
      errors.empty?
    end
  end

  class Contract
    def initialize(root:)
      @root = root
      @docs = File.join(root, 'docs')
    end

    def validate
      @errors = []
      @manifest = load_yaml(File.join(@root, MANIFEST_PATH), 'public-site manifest')
      @config = load_yaml(File.join(@docs, '_config.yml'), 'Jekyll configuration')
      return Result.new(@errors, 0) unless @manifest.is_a?(Hash) && @config.is_a?(Hash)

      validate_schema
      pages = validate_pages
      validate_navigation(pages)
      validate_exclusions(pages)
      validate_domain
      validate_header
      validate_visual_shell
      validate_ci
      validate_generated_documentation(pages)
      Result.new(@errors.uniq.sort, pages.length)
    end

  private

    def load_yaml(path, name)
      YAML.safe_load(File.binread(path), permitted_classes: [], permitted_symbols: [], aliases: false)
    rescue Errno::ENOENT, Psych::Exception => e
      @errors << "#{name} could not be read: #{e.message}"
      nil
    end

    def validate_schema
      unless @manifest['schema_version'] == 1
        @errors << "schema_version must be 1, got #{@manifest['schema_version'].inspect}"
      end
      unless @manifest['pages'].is_a?(Array)
        @errors << 'pages must be an array'
      end
      unless @manifest['navigation'].is_a?(Array)
        @errors << 'navigation must be an array'
      end
    end

    def validate_pages
      entries = @manifest['pages'].is_a?(Array) ? @manifest['pages'] : []
      pages = {}
      outputs = {}

      entries.each_with_index do |entry, index|
        unless entry.is_a?(Hash)
          @errors << "pages[#{index}] must be an object"
          next
        end

        source = entry['source']
        output = entry['output']
        classification = entry['classification']
        validate_relative_path(source, "pages[#{index}].source")
        validate_relative_path(output, "pages[#{index}].output")
        unless CLASSIFICATIONS.include?(classification)
          @errors << "pages[#{index}].classification must be one of #{CLASSIFICATIONS.join(', ')}"
        end
        if pages.key?(source)
          @errors << "duplicate page source: #{source.inspect}"
        elsif source.is_a?(String)
          pages[source] = entry
        end
        if outputs.key?(output)
          @errors << "duplicate page output: #{output.inspect}"
        elsif output.is_a?(String)
          outputs[output] = source
        end
      end

      actual_sources = documentation_sources
      (actual_sources - pages.keys).each { |path| @errors << "unclassified documentation page: #{path}" }
      (pages.keys - actual_sources).each { |path| @errors << "classified documentation page is missing: #{path}" }
      pages
    end

    def documentation_sources
      Dir.glob(File.join(@docs, '**', '*')).select do |path|
        next false unless File.file?(path)

        relative = Pathname.new(path).relative_path_from(Pathname.new(@docs)).to_s.tr('\\', '/')
        next false if relative.split('/').any? { |part| part.start_with?('_') }

        %w[.html .markdown .md].include?(File.extname(relative).downcase)
      end.map do |path|
        Pathname.new(path).relative_path_from(Pathname.new(@docs)).to_s.tr('\\', '/')
      end.sort
    end

    def validate_navigation(pages)
      entries = @manifest['navigation'].is_a?(Array) ? @manifest['navigation'] : []
      targets = {}

      entries.each_with_index do |entry, index|
        unless entry.is_a?(Hash)
          @errors << "navigation[#{index}] must be an object"
          next
        end

        title = entry['title']
        target = entry['target']
        if !title.is_a?(String) || title.strip.empty?
          @errors << "navigation[#{index}].title must be a non-empty string"
        end
        validate_navigation_target(target, index)
        if targets.key?(target)
          @errors << "duplicate navigation target: #{target.inspect}"
        elsif target.is_a?(String)
          targets[target] = true
        end

        output = target.is_a?(String) ? target.sub(%r{\A/}, '') : nil
        page = pages.values.find { |candidate| candidate['output'] == output }
        if page.nil?
          @errors << "navigation target does not name a classified page: #{target.inspect}"
        elsif page['classification'] == 'repository_only'
          @errors << "repository-only page is top-level navigable: #{page['source']}"
        end
      end
    end

    def validate_navigation_target(target, index)
      unless target.is_a?(String) && target.start_with?('/')
        @errors << "navigation[#{index}].target must be a root-relative path"
        return
      end
      if target.start_with?('//') || target.include?('\\') || target.include?('?') || target.include?('#') || target.split('/').include?('..')
        @errors << "navigation[#{index}].target is unsafe: #{target.inspect}"
      end
    end

    def validate_exclusions(pages)
      excludes = @config['exclude'].is_a?(Array) ? @config['exclude'] : []
      pages.each_value do |page|
        excluded = excludes.any? { |path| page['source'] == path || page['source'].start_with?("#{path}/") }
        if page['classification'] == 'repository_only' && !excluded
          @errors << "repository-only page is not excluded from Jekyll: #{page['source']}"
        elsif page['classification'] != 'repository_only' && excluded
          @errors << "public page is excluded from Jekyll: #{page['source']}"
        end
      end
    end

    def validate_domain
      cname_path = File.join(@docs, 'CNAME')
      cname = File.binread(cname_path)
      @errors << "docs/CNAME must be exactly #{CANONICAL_DOMAIN.inspect}" unless cname == CANONICAL_DOMAIN
      expected_url = "https://#{CANONICAL_DOMAIN}"
      @errors << "Jekyll url must be #{expected_url.inspect}" unless @config['url'] == expected_url
      unless @manifest['canonical_domain'] == CANONICAL_DOMAIN
        @errors << "canonical_domain must be #{CANONICAL_DOMAIN.inspect}"
      end
    rescue Errno::ENOENT => e
      @errors << "docs/CNAME could not be read: #{e.message}"
    end

    def validate_header
      header = File.binread(File.join(@docs, '_includes/header.html'))
      unless header.include?('site.data.public_site.navigation')
        @errors << 'header must render the explicit public-site navigation manifest'
      end
      %w[site.pages site.header_pages default_paths].each do |implicit_source|
        if header.include?(implicit_source)
          @errors << "header must not enumerate implicit navigation via #{implicit_source}"
        end
      end
    rescue Errno::ENOENT => e
      @errors << "Jekyll header could not be read: #{e.message}"
    end

    def validate_visual_shell
      default_layout = read_site_source('_layouts/default.html', 'default layout')
      home_layout = read_site_source('_layouts/home.html', 'home layout')
      page_layout = read_site_source('_layouts/page.html', 'page layout')
      header = read_site_source('_includes/header.html', 'site header')
      stylesheet = read_site_source('assets/main.scss', 'public-site stylesheet')
      return unless default_layout && home_layout && page_layout && header && stylesheet

      {
        'site shell' => 'class="site-shell"',
        'project rail' => 'class="site-rail"',
        'skip link' => 'class="skip-link"',
        'main content landmark' => 'id="main-content"',
        'shared footer' => '{%- include footer.html -%}',
      }.each do |name, marker|
        @errors << "default layout must include the #{name}" unless default_layout.include?(marker)
      end

      unless home_layout.include?('layout: default') && home_layout.include?('class="home-page"')
        @errors << 'home layout must use the shared editorial shell'
      end
      unless page_layout.include?('layout: default') && page_layout.include?('class="document-page"')
        @errors << 'page layout must use the shared editorial shell'
      end
      {
        'VM opcode reference' => 'href="{{ "/vm/opcodes.html" | relative_url }}"',
        'license' => 'href="{{ "/license.html" | relative_url }}"',
      }.each do |name, marker|
        @errors << "mobile header must link to the #{name}" unless header.include?(marker)
      end
      unless stylesheet.include?('@media (max-width: 850px)') && stylesheet.include?('@media (max-width: 560px)')
        @errors << 'public-site stylesheet must define both responsive breakpoints'
      end
      unless stylesheet.include?(':focus-visible') && stylesheet.include?('@media (prefers-reduced-motion: reduce)')
        @errors << 'public-site stylesheet must preserve focus and reduced-motion handling'
      end
    end

    def read_site_source(relative, name)
      File.binread(File.join(@docs, relative))
    rescue Errno::ENOENT => e
      @errors << "#{name} could not be read: #{e.message}"
      nil
    end

    def validate_ci
      workflow = load_yaml(File.join(@root, '.github/workflows/ruby.yml'), 'CI workflow')
      return unless workflow.is_a?(Hash)

      job = workflow.fetch('jobs', {})[CI_JOB]
      unless job.is_a?(Hash)
        @errors << "CI job #{CI_JOB} is missing"
        return
      end

      @errors << "CI job #{CI_JOB} must run on ubuntu-latest" unless job['runs-on'] == 'ubuntu-latest'
      environment = job.fetch('env', {})
      unless environment['BUNDLE_GEMFILE'] == 'docs/Gemfile'
        @errors << "CI job #{CI_JOB} must use docs/Gemfile"
      end
      steps = job.fetch('steps', [])
      setup = steps.find { |step| step['uses'] == 'ruby/setup-ruby@v1' }
      unless setup && setup.fetch('with', {}) == {'ruby-version' => '3.3.12', 'bundler-cache' => true}
        @errors << "CI job #{CI_JOB} must use Ruby 3.3.12 with the pinned documentation bundle"
      end
      unless steps.any? { |step| step['run'] == CI_COMMAND }
        @errors << "CI job #{CI_JOB} must run #{CI_COMMAND}"
      end
      if job['continue-on-error'] || steps.any? { |step| step['continue-on-error'] }
        @errors << "CI job #{CI_JOB} must remain blocking"
      end
    rescue KeyError, NoMethodError, TypeError
      @errors << "CI job #{CI_JOB} does not match the public-site contract"
    end

    def validate_generated_documentation(pages)
      declared = pages.values.select { |page| page['generated'] == true }.map { |page| page['source'] }.sort
      owned = generated_documentation_sources
      (owned - declared).each { |path| @errors << "owned generated documentation is not declared generated: #{path}" }
      (declared - owned).each { |path| @errors << "page is declared generated but is not owned by the complete gate: #{path}" }
      pages.values.select { |page| page['generated'] == true }.each do |page|
        unless page['classification'] == 'public_reference'
          @errors << "generated documentation must be a public reference page: #{page['source']}"
        end
      end
    end

    def generated_documentation_sources
      Dab::CompleteGate::GeneratedDocumentation::TRACKED_PATHS.flat_map do |relative|
        path = File.join(@root, relative)
        candidates = File.directory?(path) ? Dir.glob(File.join(path, '**', '*.md')) : [path]
        candidates.select { |candidate| File.file?(candidate) }.map do |candidate|
          Pathname.new(candidate).relative_path_from(Pathname.new(@docs)).to_s.tr('\\', '/')
        end
      end.uniq.sort
    end

    def validate_relative_path(path, location)
      if !path.is_a?(String) || path.empty? || path.start_with?('/') || path.include?('\\') || path.split('/').include?('..')
        @errors << "#{location} must be a safe relative path"
      end
    end
  end

  class BuiltSite
    LINK_PATTERN = /(?:href|src)=["']([^"']+)["']/i.freeze

    def initialize(root:, destination:)
      @root = root
      @destination = destination
      @docs = File.join(root, 'docs')
    end

    def validate
      @errors = []
      @manifest = YAML.safe_load(File.binread(File.join(@root, MANIFEST_PATH)), aliases: false)
      pages = @manifest.fetch('pages')
      public_pages = pages.reject { |page| page['classification'] == 'repository_only' }
      internal_pages = pages.select { |page| page['classification'] == 'repository_only' }

      validate_outputs(public_pages, internal_pages)
      validate_navigation(public_pages)
      validate_links(public_pages)
      validate_canonical_urls(public_pages)
      validate_built_cname
      Result.new(@errors.uniq.sort, pages.length)
    rescue Errno::ENOENT, KeyError, Psych::Exception => e
      Result.new(["built-site validation could not load its contract: #{e.message}"], 0)
    end

  private

    def validate_outputs(public_pages, internal_pages)
      public_outputs = public_pages.map { |page| page['output'] }.sort
      public_outputs.each do |output|
        @errors << "declared public page is missing from built site: #{output}" unless File.file?(built_path(output))
      end
      internal_pages.each do |page|
        if File.exist?(built_path(page['output']))
          @errors << "repository-only page was emitted by Jekyll: #{page['output']}"
        end
      end

      actual_html = Dir.glob(File.join(@destination, '**', '*.html')).map do |path|
        Pathname.new(path).relative_path_from(Pathname.new(@destination)).to_s.tr('\\', '/')
      end.sort
      (actual_html - public_outputs).each { |output| @errors << "unclassified HTML was emitted by Jekyll: #{output}" }
    end

    def validate_navigation(public_pages)
      expected = @manifest.fetch('navigation').map { |item| [item['title'], item['target']] }
      public_pages.each do |page|
        next unless page['output'].end_with?('.html') && File.file?(built_path(page['output']))

        html = File.binread(built_path(page['output']))
        trigger = html[/<div class="trigger">(.*?)<\/div>/m, 1]
        actual = trigger.to_s.scan(/<a class="page-link" href="([^"]+)">([^<]+)<\/a>/).map do |target, title|
          [CGI.unescapeHTML(title.strip), CGI.unescapeHTML(target)]
        end
        @errors << "built navigation differs on #{page['output']}: #{actual.inspect}" unless actual == expected
      end
    end

    def validate_links(public_pages)
      public_pages.each do |page|
        next unless page['output'].end_with?('.html') && File.file?(built_path(page['output']))

        html = File.binread(built_path(page['output']))
        html.scan(LINK_PATTERN).flatten.uniq.each do |target|
          link_error = validate_link(target, page['output'])
          @errors << link_error if link_error
        end
      end
    end

    def validate_link(target, source_output)
      return if target.empty? || target.start_with?('#', 'mailto:', 'tel:', 'data:')
      return "unsafe link target in #{source_output}: #{target}" if target.start_with?('javascript:', '//')

      uri = URI.parse(target)
      if uri.scheme
        return unless %w[http https].include?(uri.scheme)
        return unless uri.host == CANONICAL_DOMAIN
      end

      path = uri.path
      return if path.nil? || path.empty?

      candidate = if path.start_with?('/')
                    path.sub(%r{\A/}, '')
                  else
                    File.join(File.dirname(source_output), path)
                  end
      candidate = 'index.html' if candidate.empty?
      candidate = File.join(candidate, 'index.html') if candidate.end_with?('/')
      candidate = Pathname.new(candidate).cleanpath.to_s
      return "unsafe local link in #{source_output}: #{target}" if candidate == '..' || candidate.start_with?('../')
      return if File.file?(built_path(candidate))

      "broken local link in #{source_output}: #{target}"
    rescue URI::InvalidURIError
      "invalid link target in #{source_output}: #{target}"
    end

    def validate_canonical_urls(public_pages)
      expected_prefix = "https://#{CANONICAL_DOMAIN}"
      public_pages.each do |page|
        next unless page['output'].end_with?('.html') && File.file?(built_path(page['output']))

        html = File.binread(built_path(page['output']))
        canonical = html[/<link rel="canonical" href="([^"]+)"\s*\/?\s*>/, 1]
        if canonical.nil? || !canonical.start_with?(expected_prefix)
          @errors << "canonical URL drift in #{page['output']}: #{canonical.inspect}"
        end
      end
    end

    def validate_built_cname
      cname = File.binread(built_path('CNAME'))
      @errors << "built CNAME must be exactly #{CANONICAL_DOMAIN.inspect}" unless cname == CANONICAL_DOMAIN
    rescue Errno::ENOENT => e
      @errors << "built CNAME is missing: #{e.message}"
    end

    def built_path(relative)
      File.join(@destination, relative)
    end
  end

  class Runner
    def initialize(root:, output: $stdout, error: $stderr)
      @root = root
      @output = output
      @error = error
    end

    def run
      contract = Contract.new(root: @root).validate
      return report_failure('contract', contract.errors) unless contract.success?

      Dir.mktmpdir('dab-public-site') do |destination|
        return 1 unless build(destination)

        built_site = BuiltSite.new(root: @root, destination: destination).validate
        return report_failure('built site', built_site.errors) unless built_site.success?
      end

      @output.puts "public site: OK (#{contract.page_count} classified pages; disposable build and link smoke passed)"
      0
    end

  private

    def build(destination)
      environment = {'BUNDLE_GEMFILE' => File.join(@root, 'docs/Gemfile')}
      command = [
        'bundle', 'exec', 'jekyll', 'build',
        '--source', File.join(@root, 'docs'),
        '--destination', destination,
        '--disable-disk-cache',
        '--quiet'
      ]
      output, error, status = Open3.capture3(environment, *command, chdir: @root)
      return true if status.success?

      @error.puts 'public site: Jekyll build FAILED'
      @error.write(output)
      @error.write(error)
      false
    rescue SystemCallError => e
      @error.puts "public site: Jekyll build could not run: #{e.message}"
      false
    end

    def report_failure(stage, errors)
      @error.puts "public site: #{stage} FAILED"
      errors.each { |message| @error.puts "  #{message}" }
      1
    end
  end
end
