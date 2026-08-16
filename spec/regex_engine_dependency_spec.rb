require 'spec_helper'

require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'stringio'
require 'tmpdir'
require 'zlib'

require_relative '../lib/dab/regex_engine_dependency'

class RegexEngineFakeHttp
  def initialize(response)
    @response = response
  end

  def request(_request)
    yield @response
  end
end

describe Dab::RegexEngineDependency do
  let(:root) { File.expand_path('..', __dir__) }
  let(:canonical_config) { JSON.parse(File.binread(File.join(root, 'config/regex_engine.json'))) }

  def archive(entries)
    tar_buffer = StringIO.new(''.b)
    Gem::Package::TarWriter.new(tar_buffer) do |tar|
      tar.mkdir('pcre2-10.47', 0o755)
      entries.each do |name, value|
        case value
        when :directory
          tar.mkdir(name, 0o755)
        when Array
          tar.add_symlink(name, value.fetch(0), 0o777)
        else
          tar.add_file_simple(name, 0o644, value.bytesize) { |file| file.write(value) }
        end
      end
    end
    compressed = StringIO.new(''.b)
    Zlib::GzipWriter.wrap(compressed) { |gzip| gzip.write(tar_buffer.string) }
    compressed.string
  end

  def response(status, body: '', location: nil)
    klass = status == 200 ? Net::HTTPOK : Net::HTTPFound
    result = klass.new('1.1', status.to_s, status == 200 ? 'OK' : 'Found')
    result.body = body
    result.define_singleton_method(:read_body) do |&block|
      block.call(body)
    end
    result['location'] = location if location
    result
  end

  def rewrite_entry_type(archive_bytes, name, typeflag)
    tar = Zlib::GzipReader.wrap(StringIO.new(archive_bytes), &:read)
    header = (0...tar.bytesize).step(512).find do |offset|
      tar.byteslice(offset, 100).split("\0", 2).first == name
    end
    raise "missing tar entry #{name}" unless header

    tar.setbyte(header + 156, typeflag.ord)
    rewritten = StringIO.new(''.b)
    Zlib::GzipWriter.wrap(rewritten) { |gzip| gzip.write(tar) }
    rewritten.string
  end

  def with_dependency(entries: nil, archive_bytes: nil, configuration: {}, responses: [], before_publish: nil)
    Dir.mktmpdir('dab-regex-engine-dependency') do |temporary_root|
      bytes = archive_bytes || archive(entries || canonical_entries)
      config = canonical_config.merge(
        'size' => bytes.bytesize,
        'sha256' => Digest::SHA256.hexdigest(bytes),
        'required_files' => canonical_required_files
      ).merge(configuration)
      FileUtils.mkdir_p(File.join(temporary_root, 'config'))
      config_path = File.join(temporary_root, 'config/regex_engine.json')
      File.binwrite(config_path, JSON.pretty_generate(config))
      queue = responses.empty? ? [response(200, body: bytes)] : responses
      dependency = described_class.new(
        root: temporary_root,
        config_path: config_path,
        http_factory: lambda { |_uri| RegexEngineFakeHttp.new(queue.shift || raise('unexpected HTTP request')) },
        before_publish: before_publish
      )
      yield dependency, temporary_root, bytes, config_path
    end
  end

  def canonical_entries
    {
      'pcre2-10.47/CMakeLists.txt' => 'cmake',
      'pcre2-10.47/NON-AUTOTOOLS-BUILD' => 'instructions',
      'pcre2-10.47/src' => :directory,
      'pcre2-10.47/src/config.h.generic' => 'config',
      'pcre2-10.47/src/pcre2.h.generic' => 'header',
      'pcre2-10.47/src/pcre2_chartables.c.dist' => 'tables',
      'pcre2-10.47/src/pcre2_compile.c' => 'source',
    }
  end

  def canonical_required_files
    canonical_entries.filter_map do |path, value|
      path.delete_prefix('pcre2-10.47/') if value.is_a?(String)
    end
  end

  it 'pins the official PCRE2 10.47 provenance and bounded download schema' do
    expect(canonical_config).to include(
      'schema_version' => 1,
      'name' => 'pcre2',
      'version' => '10.47',
      'url' => 'https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.gz',
      'sha256' => 'c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16',
      'size' => 2_792_969,
      'maximum_download_bytes' => 4 * 1024 * 1024,
      'maximum_redirects' => 3,
      'archive_root' => 'pcre2-10.47',
      'publish_directory' => 'build/dependencies/pcre2-10.47'
    )
    expect(canonical_config.fetch('required_files')).to include(
      'src/config.h.generic', 'src/pcre2.h.generic', 'src/pcre2_chartables.c.dist',
      'src/pcre2_compile.c', 'src/pcre2_valid_utf.c', 'src/pcre2_ucd.c'
    )
  end

  it 'rejects unknown schema fields and non-HTTPS URLs before network access' do
    [{'extra' => true}, {'url' => 'http://example.test/pcre2.tar.gz'}].each do |change|
      expect { with_dependency(configuration: change) { |_dependency| } }.to raise_error(
        described_class::Error
      )
    end
  end

  it 'follows only the bounded number of HTTPS redirects' do
    redirects = [
      response(302, location: 'https://assets.example.test/one'),
      response(302, location: 'https://assets.example.test/two'),
      response(302, location: 'https://assets.example.test/three'),
      response(302, location: 'https://assets.example.test/four'),
    ]
    with_dependency(responses: redirects) do |dependency|
      expect { dependency.prepare! }.to raise_error(
        described_class::Error, /exceeded the redirect limit/
      )
    end
  end

  it 'stops streaming when a response exceeds the configured bound' do
    bytes = archive(canonical_entries)
    maximum_download_bytes = bytes.bytesize
    oversized = response(200, body: "#{bytes}overflow")
    with_dependency(
      archive_bytes: bytes,
      responses: [oversized],
      configuration: {'maximum_download_bytes' => maximum_download_bytes}
    ) do |dependency|
      expect { dependency.prepare! }.to raise_error(
        described_class::Error,
        "Regex engine download exceeded configured maximum of #{maximum_download_bytes} bytes"
      )
    end
  end

  it 'streams a verified archive and atomically publishes the required generic inputs' do
    with_dependency do |dependency, temporary_root|
      marker = dependency.prepare!
      publish = File.join(temporary_root, 'build/dependencies/pcre2-10.47')
      expect(marker).to eq(File.join(publish, described_class::READY_MARKER))
      expect(File.binread(File.join(publish, 'src/pcre2.h'))).to eq('header')
      expect(File.binread(File.join(publish, 'src/config.h'))).to eq('config')
      expect(File.binread(File.join(publish, 'src/pcre2_chartables.c'))).to eq('tables')
      expect(Dir[File.join(temporary_root, 'build/dependencies/.staging-*')]).to be_empty
    end
  end

  it 'fails closed on pinned size and digest mismatches' do
    [{'size' => 1}, {'sha256' => '0' * 64}].each do |change|
      with_dependency(configuration: change) do |dependency|
        expect { dependency.prepare! }.to raise_error(described_class::Error, /size|SHA-256/)
      end
    end
  end

  it 'rehashes a cached archive and rejects cache tampering without downloading' do
    with_dependency do |dependency, temporary_root|
      cache = File.join(temporary_root, 'build/dependencies/cache/pcre2-10.47.tar.gz')
      FileUtils.mkdir_p(File.dirname(cache))
      File.binwrite(cache, 'tampered')
      expect { dependency.prepare! }.to raise_error(described_class::Error, /size/)
    end
  end

  it 'rejects absolute and parent-traversing archive entries' do
    ['/absolute', 'pcre2-10.47/../escape'].each do |unsafe|
      entries = canonical_entries.merge(unsafe => 'escape')
      with_dependency(entries: entries) do |dependency|
        expect { dependency.prepare! }.to raise_error(described_class::Error, /Unsafe.*path/)
      end
    end
  end

  it 'rejects symbolic links, hardlinks, and special device entry types' do
    linked = canonical_entries.merge('pcre2-10.47/src/link' => ['pcre2_compile.c'])
    with_dependency(entries: linked) do |dependency|
      expect { dependency.prepare! }.to raise_error(described_class::Error, /entry type/)
    end

    linked_archive = archive(linked)
    hardlinked = rewrite_entry_type(linked_archive, 'pcre2-10.47/src/link', '1')
    with_dependency(archive_bytes: hardlinked) do |dependency|
      expect { dependency.prepare! }.to raise_error(described_class::Error, /entry type/)
    end

    bytes = archive(canonical_entries)
    special = rewrite_entry_type(bytes, 'pcre2-10.47/CMakeLists.txt', '3')
    with_dependency(archive_bytes: special) do |dependency|
      expect { dependency.prepare! }.to raise_error(described_class::Error, /entry type/)
    end
  end

  it 'rejects an unexpected archive root and a missing required entry' do
    wrong_root = archive(canonical_entries.transform_keys { |path| path.sub('pcre2-10.47', 'other') })
    with_dependency(archive_bytes: wrong_root) do |dependency|
      expect { dependency.prepare! }.to raise_error(described_class::Error, /archive root/)
    end

    missing = canonical_entries.reject { |path| path.end_with?('pcre2_compile.c') }
    with_dependency(entries: missing, configuration: {
      'required_files' => canonical_required_files,
    }) do |dependency|
      expect { dependency.prepare! }.to raise_error(described_class::Error, /missing required files/)
    end
  end

  it 'leaves no ready marker or partial publication when atomic publish fails' do
    failure = lambda { |_staging, _publish| raise Errno::EIO.new('injected publish failure') }
    with_dependency(before_publish: failure) do |dependency, temporary_root|
      expect { dependency.prepare! }.to raise_error(described_class::Error, /injected publish failure/)
      publish = File.join(temporary_root, 'build/dependencies/pcre2-10.47')
      expect(File.exist?(publish)).to be(false)
      expect(Dir[File.join(temporary_root, 'build/dependencies/.staging-*')]).to be_empty
    end
  end

  it 'fails closed rather than replacing a tampered published source tree' do
    with_dependency do |dependency, temporary_root|
      dependency.prepare!
      source = File.join(temporary_root, 'build/dependencies/pcre2-10.47/src/pcre2_compile.c')
      File.binwrite(source, 'tampered')
      expect { dependency.prepare! }.to raise_error(described_class::Error, /failed verification/)
      expect(File.binread(source)).to eq('tampered')
    end
  end
end
