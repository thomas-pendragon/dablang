require 'json'
require 'pathname'

require_relative 'shared_noautorun'

$autorun = true if $autorun.nil?

class DabModernSourceFixture
  SCHEMA_VERSION = 1
  EXTENSION = '.dabmtest'.freeze
  DELIMITER = "\n--- SOURCE ---\n".freeze
  FIELDS = %w[schema_version status stdout stderr].freeze

  class SchemaError < ArgumentError; end

  attr_reader :path, :source, :source_filename, :expected_status, :expected_stdout, :expected_stderr

  def self.load(path)
    new(path).tap(&:load!)
  end

  def initialize(path)
    @path = path.to_s
  end

  def load!
    validate_extension!
    metadata_text, @source = split_document(normalized_content)
    metadata = parse_metadata(metadata_text)
    validate_metadata!(metadata)

    @source_filename = "#{File.basename(path, EXTENSION)}.dabm"
    @expected_status = metadata.fetch('status')
    @expected_stdout = metadata.fetch('stdout')
    @expected_stderr = metadata.fetch('stderr')
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

  def split_document(content)
    parts = content.split(DELIMITER, -1)
    schema_error('fixture requires exactly one --- SOURCE --- delimiter') unless parts.length == 2
    parts
  end

  def parse_metadata(text)
    JSON.parse(text)
  rescue JSON::ParserError => e
    schema_error("metadata is not valid JSON: #{e.message}")
  end

  def validate_metadata!(metadata)
    schema_error("metadata must be an object, got #{type_name(metadata)}") unless metadata.is_a?(Hash)

    missing = FIELDS - metadata.keys
    unknown = metadata.keys - FIELDS
    schema_error("metadata is missing fields: #{missing.sort.join(', ')}") unless missing.empty?
    schema_error("metadata has unsupported fields: #{unknown.sort.join(', ')}") unless unknown.empty?

    unless metadata['schema_version'] == SCHEMA_VERSION
      schema_error("schema_version must be #{SCHEMA_VERSION}, got #{metadata['schema_version'].inspect}")
    end
    status = metadata['status']
    unless status.is_a?(Integer) && status.between?(0, 255)
      schema_error("status must be an Integer from 0 through 255, got #{status.inspect}")
    end
    %w[stdout stderr].each do |field|
      value = metadata[field]
      schema_error("#{field} must be a String, got #{type_name(value)}") unless value.is_a?(String)
    end
  end

  def type_name(value)
    value.nil? ? 'null' : value.class.name
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
