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

  def with_application_stdout(sections, body:)
    source = sections.fetch('SOURCE')
    {'SOURCE' => source, 'EXPECTED APPLICATION STDOUT' => body}.merge(
      sections.reject { |name| name == 'SOURCE' }
    )
  end

  it 'loads the committed versioned fixture with exact source and stream expectations' do
    fixture = described_class.load(committed_fixture)

    expect(fixture.source).to eq("this is intentionally unsupported Modern source\n")
    expect(fixture.source_filename).to eq('0001_unsupported_modern.dabm')
    expect(fixture.expected_status).to eq(2)
    expect(fixture.expected_stdout).to eq('')
    expect(fixture.expected_application_stdout).to be_nil
    expect(fixture.note).to be_nil
    expect(fixture.expected_stderr).to eq(
      'compiler: 0001_unsupported_modern.dabm:1:0: error: ' \
      "unsupported Dab syntax profile \"modern\": parser is not implemented\n"
    )
  end

  it 'loads an exact nonempty NOTE as documentation-only metadata without changing expectations' do
    note = "This fixture documents an incremental compiler boundary.\n"
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      sections = {
        'SOURCE' => "line one\nline two\n",
        'EXPECTED APPLICATION STDOUT' => "application output\n\n",
        'NOTE' => note,
        'SCHEMA VERSION' => "1\n",
        'STATUS' => "0\n",
        'STDOUT' => "first line\nsecond line\n",
      }
      path = write_fixture(directory, sections: sections)
      fixture = described_class.load(path)
      headers = File.binread(path).scan(/^## ([A-Z]+(?: [A-Z]+)*)\n/).flatten

      expect(headers.first(3)).to eq(['SOURCE', 'EXPECTED APPLICATION STDOUT', 'NOTE'])
      expect(fixture.note).to eq(note)
      expect(fixture.source).to eq("line one\nline two\n")
      expect(fixture.expected_status).to eq(0)
      expect(fixture.expected_stdout).to eq("first line\nsecond line\n")
      expect(fixture.expected_stderr).to eq('')
      expect(fixture.expected_application_stdout).to eq("application output\n")
    end
  end

  it 'loads the exact NOTE on typed-local fixture 0077 without changing its compiler contract' do
    path = File.expand_path('../test/modern_source/0077_typed_local_reassignment_mismatch.dabmtest', __dir__)
    fixture = described_class.load(path)

    expect(fixture.note).to eq(
      'This fixture characterizes an incremental compiler boundary and is not a valid Dab 0.1 program: ' \
      "a non-nullable String cannot be initialized with nil.\n"
    )
    expect(fixture.source).to eq("def main()\nvar value : String = nil\nvalue = 1\nend\n")
    expect([fixture.expected_status, fixture.expected_stdout]).to eq([2, ''])
    expect(fixture.expected_stderr).to eq(
      'compiler: 0077_typed_local_reassignment_mismatch.dabm:3:8: error: ' \
      "cannot assign Modern literal of type Fixnum to local \"value\" of type String\n"
    )
  end

  it 'uses exact section bodies and treats absent stream sections as empty' do
    Dir.mktmpdir('dab-modern-source-fixture') do |directory|
      sections = {
        'SOURCE' => "line one\nline two\n",
        'EXPECTED APPLICATION STDOUT' => "application output\n\n",
        'SCHEMA VERSION' => "1\n",
        'STATUS' => "0\n",
        'STDOUT' => "first line\nsecond line\n",
      }
      fixture = described_class.load(write_fixture(directory, sections: sections))

      expect(fixture.source).to eq("line one\nline two\n")
      expect(fixture.expected_status).to eq(0)
      expect(fixture.expected_stdout).to eq("first line\nsecond line\n")
      expect(fixture.expected_stderr).to eq('')
      expect(fixture.expected_application_stdout).to eq("application output\n")
    end
  end

  it 'loads the exact migrated runtime inventory with byte-exact output expectations' do
    expected_basenames = %w[
      0040_print_call_runtime.dabmtest
      0041_string_length_calls.dabmtest
      0046_print_member_argument.dabmtest
      0047_multibyte_member_argument.dabmtest
      0048_puts_member_argument.dabmtest
      0054_print_zero_arity.dabmtest
      0055_print_multiple_arity.dabmtest
      0056_p01_helper_call.dabmtest
      0059_fixed_local_bindings.dabmtest
      0071_p02_bind_and_print_local.dabmtest
      0072_mutable_local_reassignment.dabmtest
      0073_p03_reassign_local.dabmtest
      0074_typed_local_bindings.dabmtest
      0079_p04_use_typed_local.dabmtest
      0083_value_return.dabmtest
      0085_call_result_return.dabmtest
      0086_return_integration.dabmtest
      0087_call_result_argument.dabmtest
      0089_p05_print_returned_call_value.dabmtest
      0090_simple_string_interpolation.dabmtest
      0092_parameter_references.dabmtest
      0094_p06_interpolate_parameter.dabmtest
      0095_static_string_interpolation_folding.dabmtest
      0096_structured_if_else.dabmtest
      0097_p07_choose_value_with_if.dabmtest
      0098_structured_elsif.dabmtest
      0099_structured_unless.dabmtest
    ]
    fixture_directory = File.expand_path('../test/modern_source', __dir__)
    paths = Dir.children(fixture_directory).filter_map do |basename|
      next unless basename.end_with?('.dabmtest')

      path = File.join(fixture_directory, basename)
      transport_content = File.binread(path).gsub("\r\n", "\n")
      path if transport_content.include?("## EXPECTED APPLICATION STDOUT\n")
    end.sort

    expect(paths.map { |path| File.basename(path) }).to eq(expected_basenames)
    paths.each do |path|
      transport_content = File.binread(path).gsub("\r\n", "\n")
      headers = transport_content.scan(/^## ([A-Z]+(?: [A-Z]+)*)\n/).flatten
      expect(headers.first(2)).to eq(['SOURCE', 'EXPECTED APPLICATION STDOUT'])
      expect(described_class.load(path).expected_application_stdout).not_to be_nil
    end

    no_final_lf = described_class.load(paths.fetch(2)).expected_application_stdout
    final_lf = described_class.load(paths.fetch(4)).expected_application_stdout
    expect([no_final_lf, no_final_lf.bytes]).to eq(['3', [51]])
    expect([final_lf, final_lf.bytes]).to eq(["3\n", [51, 10]])
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
    runtime_sections = with_application_stdout(
      valid_sections.merge('STATUS' => "0\n", 'STDOUT' => "assembly\n"),
      body: "output\n"
    )
    cases = {
      section_document(valid_sections.reject { |name| name == 'STATUS' }) => 'missing sections: STATUS',
      "#{section_document(valid_sections)}## STATUS\n2\n" => 'duplicate section: STATUS',
      "#{section_document(runtime_sections)}## EXPECTED APPLICATION STDOUT\nother\n" =>
        'duplicate section: EXPECTED APPLICATION STDOUT',
      section_document(valid_sections.merge('EXTRA' => "value\n")) => 'unsupported section: EXTRA',
      section_document(runtime_sections).sub('## EXPECTED APPLICATION STDOUT', '## APPLICATION STDOUT') =>
        'unsupported section: APPLICATION STDOUT',
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
      valid_sections.merge('NOTE' => '') => 'NOTE must be omitted when empty',
      with_application_stdout(valid_sections, body: '') =>
        'EXPECTED APPLICATION STDOUT must be omitted when its expected stream is empty',
      with_application_stdout(valid_sections, body: "output\n") =>
        'EXPECTED APPLICATION STDOUT requires STATUS 0',
      with_application_stdout(valid_sections.merge('STATUS' => "0\n"), body: "output\n") =>
        'EXPECTED APPLICATION STDOUT requires a STDOUT assembly expectation',
      valid_sections.merge('EXPECTED APPLICATION STDOUT' => "misordered\n") =>
        'EXPECTED APPLICATION STDOUT must immediately follow SOURCE',
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

  it 'assembles and executes fixtures with an application-output contract' do
    Dir.mktmpdir('dab-modern-source-runner') do |directory|
      fixture = instance_double(
        DabModernSourceFixture,
        source: "def main\nprint(\"output\\n\")\nend\n",
        source_filename: 'runtime.dabm',
        expected_status: 0,
        expected_stdout: "assembly\n",
        expected_stderr: '',
        expected_application_stdout: "output\n"
      )
      allow(DabModernSourceFixture).to receive(:load).and_return(fixture)
      compiler = instance_double(DabModernSourceCompiler)
      allow(DabModernSourceCompiler).to receive(:new).and_return(compiler)
      allow(compiler).to receive(:compile).and_return(
        DabModernSourceCompiler::Result.new(status: 0, stdout: "assembly\n", stderr: '')
      )
      runner = described_class.new
      allow(runner).to receive(:assemble) do |_assembly, upper, binary_input:|
        expect(binary_input).to be(true)
        File.binwrite(upper, 'bytecode')
      end
      allow(runner).to receive(:execute) do |_rings, output, _options|
        File.binwrite(output, "output\n")
      end

      runner.run_test(
        {
          input: File.join(directory, 'runtime.dabmtest'),
          inputs: [File.join(directory, 'runtime.dabmtest')],
          test_output_prefix: 'modern_',
          test_output_dir: directory,
          stdlib: File.join(directory, 'stdlib.dabcb'),
        },
        output: StringIO.new,
        error: StringIO.new
      )

      expect(runner).to have_received(:assemble).once
      expect(runner).to have_received(:execute).with(
        [File.join(directory, 'stdlib.dabcb'), kind_of(String)],
        kind_of(String),
        '--entry=main'
      ).once
    end
  end
end
