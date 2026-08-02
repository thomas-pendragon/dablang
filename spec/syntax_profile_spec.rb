require 'spec_helper'
require 'stringio'
require 'tmpdir'

require_relative '../src/compiler/_requires'

def dab_benchmark_print!; end

class DabSyntaxProfileCompilerExit < RuntimeError
  attr_reader :code

  def initialize(code)
    @code = code
    super()
  end
end

class DabSyntaxProfileCompilerContext
  attr_reader :stdin, :stdout, :stderr

  def initialize(source)
    @stdin = StringIO.new(source)
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def exit(code)
    raise DabSyntaxProfileCompilerExit.new(code)
  end
end

describe DabSyntaxProfile do
  it 'provides stable canonical legacy and modern identities' do
    expect(described_class.fetch('legacy')).to equal(described_class::LEGACY)
    expect(described_class.fetch('modern')).to equal(described_class::MODERN)
    expect(described_class.available).to eq [described_class::LEGACY, described_class::MODERN]
    expect(described_class.available).to be_frozen
  end

  it 'has stable value equality and hashing' do
    legacy = described_class.fetch('legacy')

    expect(legacy).to eq described_class::LEGACY
    expect(legacy.eql?(described_class::LEGACY)).to be true
    expect(legacy.hash).to eq described_class::LEGACY.hash
    expect(legacy.to_s).to eq 'legacy'
  end

  it 'rejects unknown profile names deterministically' do
    expect { described_class.fetch('future') }
      .to raise_error(DabSyntaxProfileError, 'unknown Dab syntax profile "future"; available profiles: legacy, modern')
  end

  it 'rejects invalid profile names deterministically' do
    expect { described_class.fetch(:legacy) }
      .to raise_error(DabSyntaxProfileError, 'invalid Dab syntax profile name; expected a String')
  end

  it 'rejects values that are not registered profile objects' do
    [nil, 'legacy', :legacy, true].each do |invalid|
      expect { described_class.validate(invalid) }
        .to raise_error(DabSyntaxProfileError, 'invalid Dab syntax profile; expected a registered DabSyntaxProfile')
    end
  end
end

describe DabProgramStream do
  it 'defaults to the legacy profile without changing legacy parsing' do
    stream = described_class.new('identifier')

    expect(stream.syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(stream.read_identifier).to eq 'identifier'
  end

  it 'retains an explicit legacy profile' do
    stream = described_class.new('identifier', true, 'sample.dab', syntax_profile: DabSyntaxProfile::LEGACY)

    expect(stream.syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(stream.filename).to eq 'sample.dab'
    expect(stream.read_identifier).to eq 'identifier'
  end

  it 'retains the complete explicit source unit through parser construction' do
    source_unit = DabSourceUnit.new(
      input: 'sample.dab',
      syntax_profile: DabSyntaxProfile::LEGACY
    )
    stream = described_class.new('identifier', source_unit: source_unit)

    expect(stream.source_unit).to equal(source_unit)
    expect(stream.syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(stream.filename).to eq 'sample.dab'
  end

  it 'rejects modern before legacy parsing can begin' do
    expect { described_class.new('func main() {}', syntax_profile: DabSyntaxProfile::MODERN) }
      .to raise_error(
        DabUnsupportedSyntaxProfileError,
        'unsupported Dab syntax profile "modern": parser is not implemented'
      )
  end

  it 'rejects an invalid profile before parsing' do
    expect { described_class.new('identifier', syntax_profile: 'legacy') }
      .to raise_error(DabSyntaxProfileError, 'invalid Dab syntax profile; expected a registered DabSyntaxProfile')
  end

  it 'rejects ambiguous source-unit and profile arguments' do
    source_unit = DabSourceUnit.new(input: :stdin, syntax_profile: DabSyntaxProfile::LEGACY)

    expect do
      described_class.new(
        'identifier',
        source_unit: source_unit,
        syntax_profile: DabSyntaxProfile::LEGACY
      )
    end.to raise_error(
      DabSourceUnitError,
      'DabProgramStream accepts source_unit: or syntax_profile:, not both'
    )
  end

  it 'does not leak profile state across parser instances' do
    first = described_class.new('first', syntax_profile: DabSyntaxProfile::LEGACY)
    expect { described_class.new('invalid', syntax_profile: :modern) }.to raise_error(DabSyntaxProfileError)
    second = described_class.new('second')

    expect(first.syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(second.syntax_profile).to equal(DabSyntaxProfile::LEGACY)
  end
end

describe DabSourceUnit do
  it 'retains an immutable canonical profile and input identity' do
    source_unit = described_class.new(
      input: 'program.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    expect(source_unit.input).to eq 'program.dabm'
    expect(source_unit.filename).to eq 'program.dabm'
    expect(source_unit.syntax_profile).to equal(DabSyntaxProfile::MODERN)
    expect(source_unit).to be_frozen
  end

  it 'uses the characterized stdin filename and rejects invalid profiles' do
    source_unit = described_class.new(input: :stdin, syntax_profile: DabSyntaxProfile::LEGACY)

    expect(source_unit.filename).to eq '<input>'
    expect do
      described_class.new(input: 'program.dab', syntax_profile: 'legacy')
    end.to raise_error(
      DabSyntaxProfileError,
      'invalid Dab syntax profile; expected a registered DabSyntaxProfile'
    )
  end

  it 'rejects an invalid diagnostic filename with a source-unit error' do
    expect do
      described_class.new(
        input: 'program.dab',
        filename: :program,
        syntax_profile: DabSyntaxProfile::LEGACY
      )
    end.to raise_error(
      DabSourceUnitError,
      'invalid Dab source unit filename; expected a String'
    )
  end
end

describe DabModernSyntaxDiagnostics do
  it 'raises one typed zero-width entry diagnostic retaining the exact source identity' do
    parser_support_calls = 0
    instrumented_source_unit = Class.new(DabSourceUnit) do
      define_method(:require_parser_support!) do
        parser_support_calls += 1
        super()
      end
    end
    source_unit = instrumented_source_unit.new(
      input: 'physical-source.dabm',
      filename: 'diagnostic-source.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    expect do
      described_class.validate_source_units!([source_unit])
    end.to raise_error(DabModernSyntaxDiagnosticError) do |error|
      expect(error.source_location.source_unit).to equal(source_unit)
      expect(error.source_location.to_h).to eq(offset: 0, line: 1, column: 0)
      expect(error.diagnostic).to eq(
        'diagnostic-source.dabm:1:0: error: ' \
        'unsupported Dab syntax profile "modern": parser is not implemented'
      )
    end
    expect(parser_support_calls).to eq 1
  end
end

describe DabCompilerFrontend do
  def compile_result(source, syntax_profile: nil, source_units: nil, settings: {inputs: [:stdin]})
    context = DabSyntaxProfileCompilerContext.new(source)
    status = 0
    begin
      options = {}
      options[:syntax_profile] = syntax_profile if syntax_profile
      options[:source_units] = source_units if source_units
      if options.empty?
        run_dab_compiler(settings, context)
      else
        run_dab_compiler(settings, context, **options)
      end
    rescue DabSyntaxProfileCompilerExit => e
      status = e.code
    end
    [status, context.stdout.string, context.stderr.string]
  end

  it 'retains the default and explicit invocation profiles' do
    expect(described_class.new.syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(described_class.new(syntax_profile: DabSyntaxProfile::LEGACY).syntax_profile)
      .to equal(DabSyntaxProfile::LEGACY)
    expect(described_class.new(syntax_profile: DabSyntaxProfile::MODERN).syntax_profile)
      .to equal(DabSyntaxProfile::MODERN)
  end

  it 'produces byte-identical compiler output for default and explicit legacy invocations' do
    source = "func main()\n{\n\tprint(42);\n}\n"

    expect(compile_result(source, syntax_profile: DabSyntaxProfile::LEGACY)).to eq compile_result(source)
  end

  it 'produces byte-identical diagnostics for default and explicit legacy invocations' do
    source = "func main()\n{\n\tmissing_identifier;\n}\n"

    explicit = compile_result(source, syntax_profile: DabSyntaxProfile::LEGACY)
    expect(explicit).to eq compile_result(source)
    expect(explicit.first).to eq 1
    expect(explicit.last).not_to be_empty
  end

  it 'fails closed before compiler invocation for an invalid profile' do
    expect { described_class.new(syntax_profile: 'legacy') }
      .to raise_error(DabSyntaxProfileError, 'invalid Dab syntax profile; expected a registered DabSyntaxProfile')
  end

  it 'reports the unsupported modern parser profile with stable status' do
    expect(compile_result('this is not legacy syntax', syntax_profile: DabSyntaxProfile::MODERN)).to eq [
      2,
      '',
      'compiler: <input>:1:0: error: ' \
      "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
    ]
  end

  it 'validates every source unit before Ring loading or parser construction' do
    source_units = [
      DabSourceUnit.new(input: 'library.dab', syntax_profile: DabSyntaxProfile::LEGACY),
      DabSourceUnit.new(input: 'program.dabm', syntax_profile: DabSyntaxProfile::MODERN),
    ]
    expect(DabBinReader).not_to receive(:new)
    expect(DabProgramStream).not_to receive(:new)
    expect(File).not_to receive(:binread)

    result = compile_result(
      'this input must not be consumed',
      source_units: source_units,
      settings: {inputs: source_units.map(&:input), ring_base: ['must-not-load.dabcb']}
    )

    expect(result).to eq [
      2,
      '',
      'compiler: program.dabm:1:0: error: ' \
      "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
    ]
  end

  it 'compiles one zero-byte Modern upper Ring without constructing a parser' do
    Dir.mktmpdir('dab-empty-modern-source-unit') do |directory|
      source_path = File.join(directory, 'application.dabm')
      File.binwrite(source_path, ''.b)
      source_unit = DabSourceUnit.new(
        input: source_path,
        syntax_profile: DabSyntaxProfile::MODERN
      )
      lower_ring = File.join(directory, 'stdlib.dabcb')
      lower_program = DabNodeUnit.new
      lower_program.start_offset = 123
      reader = instance_double(DabBinReader)
      allow(DabBinReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:parse_ring).with(lower_ring, [], 0).and_return([lower_program, []])
      expect(DabProgramStream).not_to receive(:new)

      result = compile_result(
        'ignored stdin',
        source_units: [source_unit],
        settings: {inputs: [source_path], ring_base: [lower_ring]}
      )

      expect(result.first).to eq 0
      expect(result.last).to eq ''
      expect(result[1]).to include('W_OFFSET 123')
      expect(source_unit.syntax_profile).to equal(DabSyntaxProfile::MODERN)
    end
  end
end
