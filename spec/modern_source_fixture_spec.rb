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

  def write_fixture(directory, sections: valid_sections, extension: '.dabmtest')
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "fixture#{extension}")
    File.binwrite(path, section_document(sections))
    path
  end

  def valid_sections
    {
      'SOURCE' => "future source\n",
      'SCHEMA VERSION' => "1\n",
      'STATUS' => "2\n",
      'STDERR' => 'compiler: fixture.dabm:1:0: error: ' \
                  "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
    }
  end

  def section_document(sections)
    sections.map { |name, body| "## #{name}\n#{body}" }.join
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

  it 'uses exact section bodies and treats absent stream sections as empty' do
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      sections = {
        'STATUS' => "0\n",
        'SOURCE' => "line one\nline two\n",
        'SCHEMA VERSION' => "1\n",
        'STDOUT' => "first line\nsecond line\n",
      }
      fixture = described_class.load(write_fixture(directory, sections: sections))

      expect(fixture.source).to eq("line one\nline two\n")
      expect(fixture.expected_status).to eq(0)
      expect(fixture.expected_stdout).to eq("first line\nsecond line\n")
      expect(fixture.expected_stderr).to eq('')
    end
  end

  it 'normalizes fixture transport CRLF while retaining exact section bodies' do
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      sections = valid_sections.merge('SOURCE' => "line one\nline two\n")
      path = write_fixture(directory, sections: sections)
      content = File.binread(path).gsub("\n", "\r\n")
      File.binwrite(path, content)

      fixture = described_class.load(path)

      expect(fixture.source).to eq("line one\nline two\n")
      expect(fixture.expected_stderr).to end_with("implemented\n")
    end
  end

  it 'rejects missing, duplicate, unknown, and wrongly named sections deterministically' do
    cases = {
      section_document(valid_sections.reject { |name| name == 'STATUS' }) => 'missing sections: STATUS',
      "#{section_document(valid_sections)}## STATUS\n2\n" => 'duplicate section: STATUS',
      section_document(valid_sections.merge('EXTRA' => "value\n")) => 'unsupported section: EXTRA',
      section_document(valid_sections).sub('## STATUS', '## status') => 'invalid section header: ## status',
      "preamble\n#{section_document(valid_sections)}" => 'content before first section',
    }

    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      cases.each_with_index do |(body, diagnostic), index|
        path = File.join(directory, "#{index}.dabmtest")
        File.binwrite(path, body)

        expect { described_class.load(path) }.to raise_error(
          DabModernSourceFixture::SchemaError,
          /#{Regexp.escape(path.tr('\\', '\/'))}: fixture schema: .*#{diagnostic}/
        )
      end
    end
  end

  it 'rejects invalid scalar and empty optional-stream sections' do
    cases = {
      valid_sections.merge('SCHEMA VERSION' => "2\n") => 'SCHEMA VERSION must be 1, got 2',
      valid_sections.merge('SCHEMA VERSION' => " 1\n") => 'SCHEMA VERSION must be an integer',
      valid_sections.merge('STATUS' => "-1\n") => 'STATUS must be an Integer from 0 through 255',
      valid_sections.merge('STATUS' => "256\n") => 'STATUS must be an Integer from 0 through 255',
      valid_sections.merge('STATUS' => "2\n\n") => 'STATUS must be an integer',
      valid_sections.merge('STDOUT' => '') => 'STDOUT must be omitted when its expected stream is empty',
    }

    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      cases.each_with_index do |(sections, diagnostic), index|
        path = write_fixture(File.join(directory, index.to_s), sections: sections)

        expect { described_class.load(path) }.to raise_error(
          DabModernSourceFixture::SchemaError,
          /#{Regexp.escape(diagnostic)}/
        )
      end
    end
  end

  it 'rejects malformed section documents and the wrong fixture extension' do
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      malformed = File.join(directory, 'malformed.dabmtest')
      File.binwrite(malformed, '## SOURCE')
      wrong_extension = write_fixture(directory, extension: '.DABMTEST')

      expect { described_class.load(malformed) }
        .to raise_error(DabModernSourceFixture::SchemaError, /section header must end with LF/)
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
      sections = {
        'SOURCE' => "future source\n",
        'SCHEMA VERSION' => "1\n",
        'STATUS' => "0\n",
      }
      path = File.join(directory, 'unexpected.dabmtest')
      File.binwrite(path, sections.map { |name, body| "## #{name}\n#{body}" }.join)

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
      File.binwrite(path, "## SOURCE\nfuture source\n")
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
      end.to raise_error(DabModernSourceFixture::SchemaError, /missing sections: SCHEMA VERSION, STATUS/)

      expect(error.string).to include(
        'exception: DabModernSourceFixture::SchemaError:',
        'stage: fixture schema',
        'missing sections: SCHEMA VERSION, STATUS'
      )
      expect(error.string).not_to include('stage: compile Modern source')
    end
  end
end
