require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/shared/syntax_profile'
require_relative '../src/compiler/syntax_options'

describe 'Dab compiler --syntax option' do
  let(:project_root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(project_root, 'src/compiler/compiler.rb') }

  def invoke(*arguments)
    Open3.capture3(RbConfig.ruby, compiler, *arguments, chdir: project_root)
  end

  def with_sources(*sources, extension: '.dab')
    Dir.mktmpdir('dab-compiler-syntax-option') do |directory|
      paths = sources.each_with_index.map do |source, index|
        path = File.join(directory, "program#{index + 1}#{extension}")
        File.binwrite(path, source)
        path
      end
      yield(*paths)
    end
  end

  def with_source(source, extension: '.dab', &block)
    with_sources(source, extension: extension, &block)
  end

  it 'resolves explicit legacy to the canonical profile and removes only its option' do
    syntax_profile, arguments, explicit = DabCompilerSyntaxOptions.parse(
      ['source.dab', '--syntax=legacy', '--no-opt']
    )

    expect(syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(arguments).to eq ['source.dab', '--no-opt']
    expect(explicit).to be true
  end

  it 'preserves the absent-option profile while marking it for filename resolution' do
    syntax_profile, arguments, explicit = DabCompilerSyntaxOptions.parse(['source.dab', '--no-opt'])

    expect(syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(arguments).to eq ['source.dab', '--no-opt']
    expect(explicit).to be false
  end

  it 'maps exact lowercase source extensions to their canonical profiles' do
    expect(DabCompilerSyntaxOptions.profile_for_filename('source.dab'))
      .to equal(DabSyntaxProfile::LEGACY)
    expect(DabCompilerSyntaxOptions.profile_for_filename('source.dabm'))
      .to equal(DabSyntaxProfile::MODERN)
    expect(DabCompilerSyntaxOptions.profile_for_filename('source.DAB')).to be_nil
    expect(DabCompilerSyntaxOptions.profile_for_filename('source.DABM')).to be_nil
    expect(DabCompilerSyntaxOptions.profile_for_filename(:stdin)).to be_nil
  end

  it 'assigns canonical inferred profiles independently to every source unit' do
    inputs = ['library.dab', 'program.dabm', 'fallback.DABM', :stdin]
    source_units = DabCompilerSyntaxOptions.resolve_inputs(
      syntax_profile: DabSyntaxProfile::LEGACY,
      explicit: false,
      inputs: inputs
    )

    expect(source_units.map(&:input)).to eq inputs
    expect(source_units.map(&:syntax_profile)).to eq [
      DabSyntaxProfile::LEGACY,
      DabSyntaxProfile::MODERN,
      DabSyntaxProfile::LEGACY,
      DabSyntaxProfile::LEGACY,
    ]
    expect(source_units.map(&:filename)).to eq [
      'library.dab',
      'program.dabm',
      'fallback.DABM',
      '<input>',
    ]
  end

  it 'gives an explicit profile precedence without consulting filenames' do
    expect(DabCompilerSyntaxOptions).not_to receive(:profile_for_filename)

    [DabSyntaxProfile::LEGACY, DabSyntaxProfile::MODERN].each do |profile|
      source_units = DabCompilerSyntaxOptions.resolve_inputs(
        syntax_profile: profile,
        explicit: true,
        inputs: ['program.dab', 'program.dabm']
      )

      expect(source_units.map(&:syntax_profile)).to all(equal(profile))
    end
  end

  it 'retains the legacy fallback for stdin and unrecognized extensions' do
    [nil, [:stdin], ['source.DAB'], ['source.DABM'], ['source.txt']].each do |inputs|
      source_units = DabCompilerSyntaxOptions.resolve_inputs(
        syntax_profile: DabSyntaxProfile::LEGACY,
        explicit: false,
        inputs: inputs
      )

      expect(source_units.map(&:syntax_profile)).to all(equal(DabSyntaxProfile::LEGACY))
    end
  end

  it 'rejects inferred modern syntax before legacy parsing' do
    with_source('this could otherwise reach the legacy parser', extension: '.dabm') do |source|
      stdout, stderr, status = invoke(source)

      expect([stdout, stderr, status.exitstatus]).to eq [
        '',
        "compiler: unsupported Dab syntax profile \"modern\": parser is not implemented\n",
        2,
      ]
    end
  end

  it 'allows explicit legacy to override .dabm inference' do
    with_source("func main()\n{\n\tprint(42);\n}\n", extension: '.dabm') do |source|
      stdout, _stderr, status = invoke('--syntax=legacy', source)

      expect(status).to be_success
      expect(stdout).not_to be_empty
    end
  end

  it 'retains the legacy fallback for uppercase .DABM' do
    with_source("func main()\n{\n\tprint(42);\n}\n", extension: '.DABM') do |source|
      expect(invoke(source).last).to be_success
    end
  end

  it 'accepts mixed profile assignment but rejects Modern before parsing any source' do
    with_sources('not legacy source', 'also not legacy source') do |legacy_source, modern_source|
      inferred_modern_source = modern_source.sub(/\.dab\z/, '.dabm')
      File.rename(modern_source, inferred_modern_source)

      [
        [legacy_source, inferred_modern_source],
        [inferred_modern_source, legacy_source],
      ].each do |inputs|
        stdout, stderr, status = invoke(*inputs)
        expect([stdout, stderr, status.exitstatus]).to eq [
          '',
          "compiler: unsupported Dab syntax profile \"modern\": parser is not implemented\n",
          2,
        ]
      end
    end
  end

  it 'allows explicit legacy to override a mixed-extension invocation' do
    library = "func answer()\n{\n\treturn 42;\n}\n"
    program = "func main()\n{\n\tprint(answer());\n}\n"

    with_sources(library, program) do |legacy_source, modern_source|
      forced_legacy_source = modern_source.sub(/\.dab\z/, '.dabm')
      File.rename(modern_source, forced_legacy_source)

      expect(invoke('--syntax=legacy', legacy_source, forced_legacy_source).last).to be_success
    end
  end

  it 'keeps valid legacy output byte-identical when legacy is explicit' do
    with_source("func main()\n{\n\tprint(42);\n}\n") do |source|
      default = invoke(source)

      expect(invoke('--syntax=legacy', source)).to eq default
      expect(invoke(source, '--syntax=legacy')).to eq default
      expect(default.last).to be_success
    end
  end

  it 'keeps invalid legacy diagnostics byte-identical when legacy is explicit' do
    with_source("func main()\n{\n\tmissing_identifier;\n}\n") do |source|
      default = invoke(source)

      expect(invoke('--syntax=legacy', source)).to eq default
      expect(invoke(source, '--syntax=legacy')).to eq default
      expect(default.last.exitstatus).to eq 1
    end
  end

  it 'keeps multiple .dab inputs byte-identical when legacy is explicit' do
    library = "func answer()\n{\n\treturn 42;\n}\n"
    program = "func main()\n{\n\tprint(answer());\n}\n"

    with_sources(library, program) do |*sources|
      inferred = invoke(*sources)

      expect(invoke('--syntax=legacy', *sources)).to eq inferred
      expect(inferred.last).to be_success
    end
  end

  it 'fails closed for unregistered and empty profiles' do
    {
      '--syntax=future' => 'compiler: unknown Dab syntax profile "future"; available profiles: legacy, modern',
      '--syntax=' => 'compiler: unknown Dab syntax profile ""; available profiles: legacy, modern',
    }.each do |argument, diagnostic|
      stdout, stderr, status = invoke(argument)

      expect([stdout, stderr, status.exitstatus]).to eq ['', "#{diagnostic}\n", 2]
    end
  end

  it 'accepts explicit modern identity but reports its parser as unsupported' do
    stdout, stderr, status = invoke('--syntax=modern')

    expect([stdout, stderr, status.exitstatus]).to eq [
      '',
      "compiler: unsupported Dab syntax profile \"modern\": parser is not implemented\n",
      2,
    ]
  end

  it 'rejects malformed, separated, and repeated syntax options before inputs' do
    {
      ['--syntax'] => 'compiler: --syntax requires the --syntax=PROFILE spelling',
      ['--syntax', 'legacy'] => 'compiler: --syntax requires the --syntax=PROFILE spelling',
      ['--syntax=legacy', '--syntax=legacy'] => 'compiler: --syntax may be specified at most once',
      ['--syntax=modern', '--syntax=modern'] => 'compiler: --syntax may be specified at most once',
    }.each do |arguments, diagnostic|
      stdout, stderr, status = invoke(*arguments)

      expect([stdout, stderr, status.exitstatus]).to eq ['', "#{diagnostic}\n", 2]
    end
  end

  it 'does not treat a malformed syntax option as a source filename' do
    with_source("func main()\n{\n\tprint(42);\n}\n") do |source|
      stdout, stderr, status = invoke('--syntax', source)

      expect([stdout, stderr, status.exitstatus]).to eq [
        '',
        "compiler: --syntax requires the --syntax=PROFILE spelling\n",
        2,
      ]
    end
  end
end
