require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'pathname'
require 'rubygems/package'
require 'securerandom'
require 'uri'
require 'zlib'

module Dab
  class RegexEngineDependency
    class Error < StandardError; end

    SCHEMA_KEYS = %w[
      archive_root maximum_download_bytes maximum_redirects name publish_directory
      required_files schema_version sha256 size url version
    ].freeze
    READY_MARKER = '.dab-regex-engine-ready.json'.freeze
    DERIVED_FILES = {
      'src/config.h.generic' => 'src/config.h',
      'src/pcre2.h.generic' => 'src/pcre2.h',
      'src/pcre2_chartables.c.dist' => 'src/pcre2_chartables.c',
    }.freeze

    attr_reader :root, :configuration

    def self.prepare!(root: File.expand_path('../..', __dir__), **options)
      new(root: root, **options).prepare!
    end

    def initialize(root:, config_path: nil, http_factory: nil, before_publish: nil)
      @root = File.expand_path(root)
      @config_path = config_path || File.join(@root, 'config/regex_engine.json')
      @http_factory = http_factory || method(:default_http)
      @before_publish = before_publish
      @configuration = load_configuration
    end

    def marker_path
      File.join(publish_path, READY_MARKER)
    end

    def prepare!
      return marker_path if published_tree_valid?

      fail_closed_if_partial_publish
      archive = cached_archive
      verify_archive!(archive)
      publish_archive!(archive)
      marker_path
    rescue Error
      raise
    rescue StandardError => e
      raise Error.new("Regex engine dependency preparation failed: #{e.class}: #{e.message}")
    end

  private

    def load_configuration
      parsed = JSON.parse(File.binread(@config_path))
      unless parsed.is_a?(Hash) && parsed.keys.sort == SCHEMA_KEYS.sort
        raise Error.new("Regex engine configuration fields must be exactly: #{SCHEMA_KEYS.sort.join(', ')}")
      end
      raise Error.new('Regex engine schema_version must be 1') unless parsed['schema_version'] == 1
      raise Error.new('Regex engine name must be pcre2') unless parsed['name'] == 'pcre2'
      raise Error.new('Regex engine version must be 10.47') unless parsed['version'] == '10.47'

      validate_url!(parsed['url'])
      validate_hex_digest!(parsed['sha256'])
      validate_positive_integer!(parsed, 'size')
      validate_positive_integer!(parsed, 'maximum_download_bytes')
      validate_nonnegative_integer!(parsed, 'maximum_redirects')
      if parsed['size'] > parsed['maximum_download_bytes'] || parsed['maximum_download_bytes'] > 4 * 1024 * 1024
        raise Error.new('Regex engine download bounds are invalid')
      end
      unless parsed['archive_root'] == "pcre2-#{parsed['version']}"
        raise Error.new('Regex engine archive_root does not match the pinned version')
      end
      unless parsed['publish_directory'] == "build/dependencies/pcre2-#{parsed['version']}"
        raise Error.new('Regex engine publish_directory is outside the pinned dependency boundary')
      end

      files = parsed['required_files']
      unless files.is_a?(Array) && !files.empty? && files.all? { |path| safe_relative_path?(path) } && files.uniq == files
        raise Error.new('Regex engine required_files must be unique safe relative paths')
      end

      parsed.freeze
    rescue JSON::ParserError => e
      raise Error.new("Regex engine configuration is not valid JSON: #{e.message}")
    end

    def validate_url!(value)
      uri = URI.parse(value.to_s)
      return if uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.fragment.nil?

      raise Error.new('Regex engine URL must be an HTTPS URL without credentials or a fragment')
    rescue URI::InvalidURIError
      raise Error.new('Regex engine URL is invalid')
    end

    def validate_hex_digest!(value)
      return if value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)

      raise Error.new('Regex engine sha256 must be a lowercase SHA-256 digest')
    end

    def validate_positive_integer!(hash, key)
      return if hash[key].is_a?(Integer) && hash[key].positive?

      raise Error.new("Regex engine #{key} must be a positive integer")
    end

    def validate_nonnegative_integer!(hash, key)
      return if hash[key].is_a?(Integer) && hash[key] >= 0

      raise Error.new("Regex engine #{key} must be a nonnegative integer")
    end

    def dependencies_root
      File.join(@root, 'build/dependencies')
    end

    def publish_path
      File.join(@root, configuration.fetch('publish_directory'))
    end

    def cache_path
      File.join(dependencies_root, 'cache', "pcre2-#{configuration.fetch('version')}.tar.gz")
    end

    def cached_archive
      return cache_path if File.exist?(cache_path)

      FileUtils.mkdir_p(File.dirname(cache_path))
      temporary = File.join(File.dirname(cache_path), ".download-#{Process.pid}-#{SecureRandom.hex(8)}")
      begin
        download_to!(URI(configuration.fetch('url')), temporary, configuration.fetch('maximum_redirects'))
        verify_archive!(temporary)
        File.rename(temporary, cache_path)
      ensure
        FileUtils.rm_f(temporary)
      end
      cache_path
    end

    def download_to!(uri, destination, redirects_left)
      validate_url!(uri.to_s)
      http = @http_factory.call(uri)
      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          return stream_response!(response, destination)
        when Net::HTTPRedirection
          raise Error.new('Regex engine download exceeded the redirect limit') if redirects_left.zero?

          location = response['location']
          raise Error.new('Regex engine redirect omitted Location') if location.nil? || location.empty?

          return download_to!(URI.join(uri.to_s, location), destination, redirects_left - 1)
        else
          raise Error.new("Regex engine download failed with HTTP #{response.code}")
        end
      end
    end

    def default_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 60
      http
    end

    def stream_response!(response, destination)
      bytes = 0
      maximum_download_bytes = configuration.fetch('maximum_download_bytes')
      File.open(destination, 'wb', 0o600) do |file|
        response.read_body do |chunk|
          bytes += chunk.bytesize
          if bytes > maximum_download_bytes
            raise Error.new(
              "Regex engine download exceeded configured maximum of #{maximum_download_bytes} bytes"
            )
          end

          file.write(chunk)
        end
        file.flush
        file.fsync
      end
    end

    def verify_archive!(path)
      raise Error.new('Regex engine archive is missing') unless File.file?(path)
      unless File.size(path) == configuration.fetch('size')
        raise Error.new('Regex engine archive size does not match the pinned value')
      end
      unless Digest::SHA256.file(path).hexdigest == configuration.fetch('sha256')
        raise Error.new('Regex engine archive SHA-256 does not match the pinned value')
      end
    end

    def publish_archive!(archive)
      staging = File.join(dependencies_root, ".staging-#{Process.pid}-#{SecureRandom.hex(8)}")
      FileUtils.mkdir_p(staging, mode: 0o700)
      begin
        extract_safely!(archive, staging)
        extracted_root = File.join(staging, configuration.fetch('archive_root'))
        verify_required_files!(extracted_root)
        create_derived_files!(extracted_root)
        write_ready_marker!(extracted_root)
        @before_publish&.call(extracted_root, publish_path)
        File.rename(extracted_root, publish_path)
      ensure
        FileUtils.rm_rf(staging)
      end
    end

    def extract_safely!(archive, staging)
      seen = {}
      root = configuration.fetch('archive_root')
      Zlib::GzipReader.open(archive) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            name = entry.full_name
            raise Error.new("Unsafe Regex engine archive path: #{name.inspect}") unless safe_relative_path?(name)

            first = Pathname.new(name).each_filename.first
            raise Error.new("Unexpected Regex engine archive root: #{first.inspect}") unless first == root
            raise Error.new("Duplicate Regex engine archive path: #{name}") if seen[name]

            seen[name] = true
            target = File.join(staging, name)
            case entry.header.typeflag
            when '5'
              FileUtils.mkdir_p(target, mode: 0o755)
            when '0', "\0"
              FileUtils.mkdir_p(File.dirname(target), mode: 0o755)
              File.open(target, 'wb', 0o644) { |file| IO.copy_stream(entry, file) }
            else
              raise Error.new("Unsupported Regex engine archive entry type #{entry.header.typeflag.inspect}: #{name}")
            end
          end
        end
      end
    rescue Zlib::GzipFile::Error, Gem::Package::TarInvalidError => e
      raise Error.new("Regex engine archive is invalid: #{e.message}")
    end

    def safe_relative_path?(value)
      return false unless value.is_a?(String) && !value.empty? &&
                          !value.include?("\0") && !value.include?('//')

      path = Pathname.new(value)
      !path.absolute? && path.each_filename.none? { |part| part == '..' || part == '.' || part.empty? }
    end

    def verify_required_files!(directory)
      missing = configuration.fetch('required_files').reject do |relative|
        path = File.join(directory, relative)
        File.file?(path) && !File.symlink?(path)
      end
      return if missing.empty?

      raise Error.new("Regex engine archive is missing required files: #{missing.join(', ')}")
    end

    def create_derived_files!(directory)
      DERIVED_FILES.each do |source, destination|
        source_path = File.join(directory, source)
        destination_path = File.join(directory, destination)
        FileUtils.cp(source_path, destination_path)
      end
    end

    def build_input_paths
      (configuration.fetch('required_files') + DERIVED_FILES.values).sort
    end

    def build_input_digests(directory)
      build_input_paths.to_h do |relative|
        path = File.join(directory, relative)
        unless File.file?(path) && !File.symlink?(path)
          raise Error.new("Regex engine build input failed verification: #{relative}")
        end

        [relative, Digest::SHA256.file(path).hexdigest]
      end
    end

    def write_ready_marker!(directory)
      document = {
        'schema_version' => 1,
        'configuration_sha256' => Digest::SHA256.file(@config_path).hexdigest,
        'archive_sha256' => configuration.fetch('sha256'),
        'build_inputs' => build_input_digests(directory),
      }
      path = File.join(directory, READY_MARKER)
      File.open(path, 'wb', 0o644) do |file|
        file.write(JSON.pretty_generate(document))
        file.write("\n")
        file.flush
        file.fsync
      end
    end

    def published_tree_valid?
      return false unless Dir.exist?(publish_path)
      return false unless File.file?(marker_path) && !File.symlink?(marker_path)

      marker = JSON.parse(File.binread(marker_path))
      expected = {
        'schema_version' => 1,
        'configuration_sha256' => Digest::SHA256.file(@config_path).hexdigest,
        'archive_sha256' => configuration.fetch('sha256'),
        'build_inputs' => build_input_digests(publish_path),
      }
      marker == expected
    rescue JSON::ParserError, Errno::ENOENT
      false
    end

    def fail_closed_if_partial_publish
      return unless File.exist?(publish_path)

      raise Error.new("Regex engine published tree failed verification: #{publish_path}")
    end
  end
end
