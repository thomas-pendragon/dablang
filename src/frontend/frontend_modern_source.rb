require 'pathname'

require_relative 'shared_noautorun'

$autorun = true if $autorun.nil?

class DabModernSourceFixture
  SCHEMA_VERSION = 1
  EXTENSION = '.dabmtest'.freeze
  REQUIRED_SECTIONS = ['SOURCE', 'SCHEMA VERSION', 'STATUS'].freeze
  OPTIONAL_SECTIONS = ['STDOUT', 'STDERR', 'APPLICATION STDOUT'].freeze
  SECTIONS = (REQUIRED_SECTIONS + OPTIONAL_SECTIONS).freeze

  class SchemaError < ArgumentError; end

  attr_reader :path, :source, :source_filename, :expected_status, :expected_stdout, :expected_stderr,
              :expected_application_stdout

  def self.load(path)
    new(path).tap(&:load!)
  end

  def initialize(path)
    @path = path.to_s
  end

  def load!
    validate_extension!
    sections = parse_sections(normalized_content)
    validate_sections!(sections)

    @source = sections.fetch('SOURCE')
    @source_filename = "#{File.basename(path, EXTENSION)}.dabm"
    @expected_status = parse_status(sections.fetch('STATUS'))
    @expected_stdout = sections.fetch('STDOUT', '')
    @expected_stderr = sections.fetch('STDERR', '')
    @expected_application_stdout = sections['APPLICATION STDOUT']
    self
  rescue Errno::ENOENT, Errno::EACCES => e
    schema_error("fixture is not readable: #{e.message}")
  end

private

  def normalized_content
    File.binread(path).gsub("\r\n", "\n")
  end

  def validate_extension!
    return if File.extname(path) == EXTENSION

    schema_error("fixture must use the exact lowercase #{EXTENSION} extension")
  end

  def parse_sections(content)
    DabFixtureSectionDocument.parse(content).sections
  rescue DabFixtureSectionDocument::ParseError => e
    schema_error(e.message)
  end

  def validate_sections!(sections)
    missing = REQUIRED_SECTIONS - sections.keys
    unknown = sections.keys - SECTIONS
    schema_error("missing sections: #{missing.join(', ')}") unless missing.empty?
    schema_error("unsupported section: #{unknown.join(', ')}") unless unknown.empty?

    schema_version = parse_integer('SCHEMA VERSION', sections.fetch('SCHEMA VERSION'))
    unless schema_version == SCHEMA_VERSION
      schema_error("SCHEMA VERSION must be #{SCHEMA_VERSION}, got #{schema_version}")
    end

    OPTIONAL_SECTIONS.each do |name|
      next unless sections.key?(name) && sections.fetch(name).empty?

      schema_error("#{name} must be omitted when its expected stream is empty")
    end

    return unless sections.key?('APPLICATION STDOUT')

    schema_error('APPLICATION STDOUT requires STATUS 0') unless parse_status(sections.fetch('STATUS')).zero?
    schema_error('APPLICATION STDOUT requires a STDOUT assembly expectation') unless sections.key?('STDOUT')
  end

  def parse_status(text)
    status = parse_integer('STATUS', text)
    unless status.between?(0, 255)
      schema_error("STATUS must be an Integer from 0 through 255, got #{status}")
    end
    status
  end

  def parse_integer(name, text)
    unless /\A-?(?:0|[1-9][0-9]*)\n?\z/.match?(text)
      schema_error("#{name} must be an integer without surrounding whitespace, got #{text.inspect}")
    end
    Integer(text, 10)
  end

  def schema_error(message)
    raise SchemaError.new("#{portable_path(path)}: fixture schema: #{message}")
  end

  def portable_path(value)
    value.to_s.tr('\\', '/')
  end
end

class DabModernSourceCompiler
  Result = Struct.new(:status, :stdout, :stderr, keyword_init: true)

  def build_source_unit(fixture, source_path)
    DabSourceUnit.new(
      input: source_path,
      filename: fixture.source_filename,
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def compile(fixture, source_path:, ring_base: nil)
    context = InlineCompilerContext.new
    source_unit = build_source_unit(fixture, source_path)
    status = 0
    settings = {inputs: [source_path]}
    settings[:ring_base] = [ring_base] if ring_base

    begin
      run_dab_compiler(settings, context, source_units: [source_unit])
    rescue InlineCompilerExit => e
      status = e.code
    end

    Result.new(status: status, stdout: context.stdout.string, stderr: context.stderr.string)
  end
end

class DabModernSourceExpectationError < RuntimeError; end

class ModernSourceSpec
  include BaseFrontend

  def run_test(settings, output: $stdout, error: $stderr)
    @settings = settings
    DabTestOutput.with_test(input, output: output, error: error) { run(settings) }
  end

  def run(settings)
    FileUtils.mkdir_p(test_output_dir)
    output_marker = temp_file('out')
    FileUtils.rm_f(output_marker)

    fixture = with_harness_action('fixture schema', "parse modern-source fixture #{portable_path(input)}") do
      DabModernSourceFixture.load(input)
    end
    source_path = temp_file('dabm')
    with_harness_action('extract Modern source', "write #{portable_path(source_path)}") do
      File.binwrite(source_path, fixture.source)
    end
    result = with_harness_action(
      'compile Modern source',
      "compile #{fixture.source_filename} with DabSyntaxProfile::MODERN"
    ) do
      ring_base = settings[:stdlib] || Array(settings[:ring_base]).first
      DabModernSourceCompiler.new.compile(fixture, source_path: source_path, ring_base: ring_base)
    end
    with_harness_action('compare compiler result', "compare exact status/stdout/stderr for #{portable_path(input)}") do
      compare_result(fixture, result)
    end
    run_application(fixture, result, settings) if fixture.expected_application_stdout

    File.binwrite(output_marker, '1')
  end

private

  def with_harness_action(stage, command, &block)
    description = "Modern fixture #{stage}: #{command}"
    DabTestOutput.with_action(stage, command: command) do
      warn description
      result = block.call
      warn "#{description} [OK]"
      result
    end
  end

  def compare_result(fixture, result)
    compare_field('status', result.status, fixture.expected_status)
    compare_field('stdout', result.stdout, fixture.expected_stdout)
    compare_field('stderr', result.stderr, fixture.expected_stderr)
  end

  def run_application(fixture, result, settings)
    ring_base = settings[:stdlib] || Array(settings[:ring_base]).first
    unless ring_base
      raise DabModernSourceExpectationError.new(
        "#{portable_path(input)}: application expectation: lower Ring is required"
      )
    end

    assembly_path = temp_file('asm')
    upper_ring = temp_file('dabcb')
    application_stdout = temp_file('application.stdout')
    FileUtils.rm_f(application_stdout)

    with_harness_action('prepare application', "write #{portable_path(assembly_path)}") do
      File.binwrite(assembly_path, result.stdout)
    end
    assemble(assembly_path, upper_ring)
    execute([ring_base, upper_ring], application_stdout, '--entry=main')
    with_harness_action(
      'compare application output',
      "compare exact application stdout for #{portable_path(input)}"
    ) do
      actual = File.binread(application_stdout)
      next if actual == fixture.expected_application_stdout

      raise DabModernSourceExpectationError.new(
        "#{portable_path(input)}: application expectation: " \
        "expected stdout #{fixture.expected_application_stdout.inspect} " \
        "(#{fixture.expected_application_stdout.bytesize} bytes), " \
        "got #{actual.inspect} (#{actual.bytesize} bytes)"
      )
    end
  end

  def compare_field(field, actual, expected)
    return if actual == expected

    detail = if field == 'status'
               "expected status #{expected}, got #{actual}"
             else
               "expected #{field} #{expected.inspect} (#{expected.bytesize} bytes), " \
                 "got #{actual.inspect} (#{actual.bytesize} bytes)"
             end
    raise DabModernSourceExpectationError.new(
      "#{portable_path(input)}: compiler expectation: #{detail}"
    )
  end

  def portable_path(value)
    value.to_s.tr('\\', '/')
  end
end

if $autorun
  read_args!
  raise "no #{DabModernSourceFixture::EXTENSION}" unless $settings[:input].end_with?(DabModernSourceFixture::EXTENSION)

  ModernSourceSpec.new.run_test($settings)
end
