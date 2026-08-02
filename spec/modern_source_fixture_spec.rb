require 'spec_helper'

require 'fileutils'
require 'stringio'
require 'tmpdir'

previous_autorun = defined?($autorun) ? $autorun : nil
$autorun = false
require_relative '../src/frontend/frontend_modern_source'
$autorun = previous_autorun

describe DabModernSourceFixture do
  let(:committed_fixture) do
    File.expand_path('../test/modern_source/0001_unsupported_modern.dabmtest', __dir__)
  end

  def write_fixture(directory, metadata:, source: "future source\n", extension: '.dabmtest')
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "fixture#{extension}")
    body = "#{JSON.pretty_generate(metadata)}\n--- SOURCE ---\n#{source}"
    File.binwrite(path, body)
    path
  end

  def valid_metadata
    {
      'schema_version' => 1,
      'status' => 2,
      'stdout' => '',
      'stderr' => 'compiler: fixture.dabm:1:0: error: ' \
                  "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
    }
  end

  it 'loads the committed versioned fixture with exact source and stream expectations' do
    fixture = described_class.load(committed_fixture)

    expect(fixture.source).to eq("this is intentionally unsupported Modern source\n")
    expect(fixture.source_filename).to eq('0001_unsupported_modern.dabm')
    expect(fixture.expected_status).to eq(2)
    expect(fixture.expected_stdout).to eq('')
    expect(fixture.expected_stderr).to eq(
      'compiler: 0001_unsupported_modern.dabm:1:0: error: ' \
      "unsupported Dab syntax profile \"modern\": parser is not implemented\n"
    )
  end

  it 'normalizes fixture transport CRLF while retaining exact expected stream strings' do
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      path = write_fixture(directory, metadata: valid_metadata, source: "line one\nline two\n")
      content = File.binread(path).gsub("\n", "\r\n")
      File.binwrite(path, content)

      fixture = described_class.load(path)

      expect(fixture.source).to eq("line one\nline two\n")
      expect(fixture.expected_stderr).to end_with("implemented\n")
    end
  end

  it 'rejects schema defects separately with the fixture path and field attribution' do
    cases = {
      {'schema_version' => 2, 'status' => 2, 'stdout' => '', 'stderr' => ''} => 'schema_version',
      {'schema_version' => 1, 'status' => -1, 'stdout' => '', 'stderr' => ''} => 'status',
      {'schema_version' => 1, 'status' => 2, 'stdout' => [], 'stderr' => ''} => 'stdout',
      {'schema_version' => 1, 'status' => 2, 'stdout' => '', 'stderr' => '', 'extra' => true} => 'unsupported fields',
    }

    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      cases.each_with_index do |(metadata, diagnostic), index|
        path = write_fixture(File.join(directory, index.to_s), metadata: metadata)

        expect { described_class.load(path) }.to raise_error(
          DabModernSourceFixture::SchemaError,
          /#{Regexp.escape(path.tr('\\', '\/'))}: fixture schema: .*#{diagnostic}/
        )
      end
    end
  end

  it 'rejects malformed metadata, missing delimiters, and the wrong fixture extension' do
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      malformed = File.join(directory, 'malformed.dabmtest')
      File.binwrite(malformed, "{\n--- SOURCE ---\nsource\n")
      missing_delimiter = File.join(directory, 'missing.dabmtest')
      File.binwrite(missing_delimiter, JSON.generate(valid_metadata))
      wrong_extension = write_fixture(directory, metadata: valid_metadata, extension: '.DABMTEST')

      expect { described_class.load(malformed) }
        .to raise_error(DabModernSourceFixture::SchemaError, /metadata is not valid JSON/)
      expect { described_class.load(missing_delimiter) }
        .to raise_error(DabModernSourceFixture::SchemaError, /requires exactly one --- SOURCE --- delimiter/)
      expect { described_class.load(wrong_extension) }
        .to raise_error(DabModernSourceFixture::SchemaError, /must use the exact lowercase \.dabmtest extension/)
    end
  end
end

describe DabModernSourceCompiler do
  let(:fixture_path) do
    File.expand_path('../test/modern_source/0001_unsupported_modern.dabmtest', __dir__)
  end
  let(:fixture) { DabModernSourceFixture.load(fixture_path) }

  it 'builds one source unit with the canonical Modern profile and stable diagnostic filename' do
    source_unit = described_class.new.build_source_unit(fixture, '/tmp/extracted-source.dabm')

    expect(source_unit.input).to eq('/tmp/extracted-source.dabm')
    expect(source_unit.filename).to eq('0001_unsupported_modern.dabm')
    expect(source_unit.syntax_profile).to equal(DabSyntaxProfile::MODERN)
  end

  it 'captures the established unsupported-Modern compiler boundary exactly' do
    Dir.mktmpdir('dab-modern-source-compiler') do |directory|
      source_path = File.join(directory, fixture.source_filename)
      File.binwrite(source_path, fixture.source)

      result = described_class.new.compile(fixture, source_path: source_path)

      expect([result.status, result.stdout, result.stderr]).to eq(
        [fixture.expected_status, fixture.expected_stdout, fixture.expected_stderr]
      )
    end
  end
end

describe ModernSourceSpec do
  let(:fixture_path) do
    File.expand_path('../test/modern_source/0001_unsupported_modern.dabmtest', __dir__)
  end

  around do |example|
    begin
      verbose = ENV.delete('DAB_TEST_VERBOSE')
      example.run
    ensure
      if verbose
        ENV['DAB_TEST_VERBOSE'] = verbose
      else
        ENV.delete('DAB_TEST_VERBOSE')
      end
    end
  end

  it 'runs the committed control fixture and writes its Rake completion marker' do
    Dir.mktmpdir('dab-modern-source-runner') do |directory|
      output = StringIO.new
      error = StringIO.new
      settings = {
        input: fixture_path,
        inputs: [fixture_path],
        test_output_prefix: 'modern_',
        test_output_dir: directory,
      }

      described_class.new.run_test(settings, output: output, error: error)

      expect(File).to exist(File.join(directory, 'modern_0001_unsupported_modern.out'))
      expect(output.string).to eq("PASS #{fixture_path}\n")
      expect(error.string).to eq('')
    end
  end

  it 'exposes attributed harness actions only in explicit verbose mode' do
    ENV['DAB_TEST_VERBOSE'] = '1'

    Dir.mktmpdir('dab-modern-source-runner') do |directory|
      output = StringIO.new
      error = StringIO.new
      settings = {
        input: fixture_path,
        inputs: [fixture_path],
        test_output_prefix: 'modern_',
        test_output_dir: directory,
      }

      described_class.new.run_test(settings, output: output, error: error)

      expect(output.string).to eq("PASS #{fixture_path}\n")
      expect(error.string).to include(
        'Modern fixture fixture schema:',
        'Modern fixture compile Modern source:',
        'DabSyntaxProfile::MODERN',
        'Modern fixture compare compiler result:'
      )
    end
  end

  it 'attributes exact compiler expectation mismatches separately from schema errors' do
    Dir.mktmpdir('dab-modern-source-runner') do |directory|
      output = StringIO.new
      error = StringIO.new
      metadata = {
        'schema_version' => 1,
        'status' => 0,
        'stdout' => '',
        'stderr' => '',
      }
      path = File.join(directory, 'unexpected.dabmtest')
      File.binwrite(path, "#{JSON.pretty_generate(metadata)}\n--- SOURCE ---\nfuture source\n")

      expect do
        settings = {
          input: path,
          inputs: [path],
          test_output_prefix: 'modern_',
          test_output_dir: directory,
        }
        described_class.new.run_test(settings, output: output, error: error)
      end.to raise_error(DabModernSourceExpectationError, /expected status 0, got 2/)

      expect(error.string).to include(
        'exception: DabModernSourceExpectationError:',
        'stage: compare compiler result',
        'expected status 0, got 2'
      )
      expect(error.string).not_to include('exception: DabModernSourceFixture::SchemaError:')
    end
  end

  it 'fails at the attributed schema stage without invoking the compiler boundary' do
    Dir.mktmpdir('dab-modern-source-runner') do |directory|
      path = File.join(directory, 'malformed.dabmtest')
      File.binwrite(path, "{}\n--- SOURCE ---\nfuture source\n")
      output = StringIO.new
      error = StringIO.new
      settings = {
        input: path,
        inputs: [path],
        test_output_prefix: 'modern_',
        test_output_dir: directory,
      }

      expect(DabModernSourceCompiler).not_to receive(:new)
      expect do
        described_class.new.run_test(settings, output: output, error: error)
      end.to raise_error(DabModernSourceFixture::SchemaError, /metadata is missing fields/)

      expect(error.string).to include(
        'exception: DabModernSourceFixture::SchemaError:',
        'stage: fixture schema',
        'metadata is missing fields: schema_version, status, stderr, stdout'
      )
      expect(error.string).not_to include('stage: compile Modern source')
    end
  end
end
