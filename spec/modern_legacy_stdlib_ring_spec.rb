require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/syntax_options'

describe 'empty Modern application over a compiled Legacy standard-library Ring' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }

  def invoke(*command, input: nil)
    Open3.capture3(*command, stdin_data: input, chdir: root)
  end

  def build_stdlib(directory, basename: 'stdlib')
    artifact = File.join(directory, "#{basename}.dabcb")
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq [0, "PASS #{artifact}\n"]
    expect(stderr).not_to include('exception:', 'FAILED')
    expect(File.binread(artifact)).to start_with('DAB'.b)
    artifact
  end

  def compile_application(directory, ring:, source: ''.b, basename: 'application', extra_inputs: [])
    source_path = File.join(directory, "#{basename}.dabm")
    File.binwrite(source_path, source)
    arguments = [RbConfig.ruby, compiler, source_path, *extra_inputs]
    arguments << "--ring-base[]=#{ring}" if ring
    assembly, stderr, compiler_status = invoke(*arguments)
    return [source_path, assembly, nil, stderr, compiler_status] unless compiler_status.success?

    bytecode, assembler_stderr, assembler_status = invoke(RbConfig.ruby, assembler, input: assembly)
    expect(assembler_status.exitstatus).to eq 0
    expect(assembler_stderr).not_to include('exception:', 'FAILED')
    artifact = File.join(directory, "#{basename}.dabcb")
    File.binwrite(artifact, bytecode)
    [source_path, assembly, artifact, stderr, compiler_status]
  end

  def parsed_artifact(path, start_symbols: [])
    DabBinReader.new.parse_dab_binary(File.binread(path), start_symbols)
  end

  it 'builds two byte-identical mixed-profile Ring pipelines with retained Modern identity' do
    stdlib_sources = Dir.glob(File.join(root, 'stdlib/*.dab')).sort
    stdlib_units = DabCompilerSyntaxOptions.resolve_inputs(
      syntax_profile: DabSyntaxProfile::LEGACY,
      explicit: false,
      inputs: stdlib_sources
    )
    expect(stdlib_sources).not_to be_empty
    expect(stdlib_units.map(&:syntax_profile)).to all(equal(DabSyntaxProfile::LEGACY))

    Dir.mktmpdir('dab-modern-stdlib-ring-determinism') do |root_directory|
      results = Array.new(2) do |index|
        directory = File.join(root_directory, "run-#{index}")
        Dir.mkdir(directory)
        lower = build_stdlib(directory)
        source, _assembly, upper, stderr, status = compile_application(directory, ring: lower)
        expect(status.exitstatus).to eq 0
        expect(stderr).not_to include('compiler:', 'exception:', 'FAILED')

        source_unit = DabCompilerSyntaxOptions.resolve_inputs(
          syntax_profile: DabSyntaxProfile::LEGACY,
          explicit: false,
          inputs: [source]
        ).fetch(0)
        expect(source_unit.syntax_profile).to equal(DabSyntaxProfile::MODERN)
        expect(source_unit).to be_frozen

        {lower: lower, upper: upper}
      end

      first, second = results
      expect(File.binread(first.fetch(:lower))).to eq File.binread(second.fetch(:lower))
      expect(File.binread(first.fetch(:upper))).to eq File.binread(second.fetch(:upper))

      lower = parsed_artifact(first.fetch(:lower))
      upper = parsed_artifact(first.fetch(:upper), start_symbols: lower.fetch(:symbols))
      expect(lower.fetch(:header).fetch(:offset)).to eq 0
      expect(upper.fetch(:header).fetch(:offset)).to eq File.size(first.fetch(:lower))
      initialization = "__init_#{File.size(first.fetch(:lower))}"
      expect(upper.fetch(:symbols)).to eq [initialization]
      expect(upper.fetch(:functions).map { |function| function.fetch(:symbol) }).to eq [initialization]
      expect(upper.fetch(:klasses).map { |klass| klass.fetch(:symbol) }).to eq %w[Set __block_join0]

      reader = DabBinReader.new
      program, lower_symbols = reader.parse_ring(first.fetch(:lower), [], 0)
      next_ring, = reader.parse_ring(first.fetch(:upper), lower_symbols, program.start_offset)
      program.merge!(next_ring)

      expect(program.has_function?('puts')).to be_truthy
      expect(program.find_class('String').functions.map(&:identifier)).to include('chars', 'to_bool')
      expect(program.find_class('Set').functions.map(&:identifier)).to include('insert', 'has?')
    end
  end

  it 'requires the lower Ring and fails when its compiled symbol table is corrupt' do
    Dir.mktmpdir('dab-modern-stdlib-ring-dependency') do |directory|
      lower = build_stdlib(directory)
      source, _assembly, artifact, stderr, status = compile_application(directory, ring: lower)
      expect(status.exitstatus).to eq 0
      expect(stderr).not_to include('compiler:', 'exception:', 'FAILED')
      expect(artifact).not_to be_nil

      _source, _assembly, removed_artifact, removed_stderr, removed_status =
        compile_application(directory, ring: nil, basename: 'without-ring')
      expect(removed_artifact).to be_nil
      expect([removed_status.exitstatus, removed_stderr]).to eq [
        2,
        "compiler: #{File.join(directory, 'without-ring.dabm')}:1:0: error: " \
        "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
      ]

      bytes = File.binread(lower)
      header = DabBinReader.new.parse_whole_header(bytes)
      symbol_index = header.fetch(:sections).index { |section| section.fetch(:name) == 'symb' }
      symbol_length = header.fetch(:sections).fetch(symbol_index).fetch(:length)
      bytes[40 + (symbol_index * 32) + 24, 8] = [symbol_length - 1].pack('Q<')
      corrupt = File.join(directory, 'corrupt-stdlib.dabcb')
      File.binwrite(corrupt, bytes)

      _source, _assembly, corrupt_artifact, corrupt_stderr, corrupt_status =
        compile_application(directory, ring: corrupt, basename: 'corrupt-ring')
      expect(corrupt_artifact).to be_nil
      expect(corrupt_status.exitstatus).not_to eq 0
      expect(corrupt_stderr).to include('truncated symbol table')
      expect(File.binread(source)).to eq ''.b
    end
  end

  it 'rejects every non-empty Modern byte sequence with the exact 0.0.33 diagnostic' do
    Dir.mktmpdir('dab-modern-stdlib-ring-nonempty') do |directory|
      lower = build_stdlib(directory)
      ["\n".b, ' '.b, "\0".b, "func main() {}\n".b].each_with_index do |source, index|
        source_path, assembly, artifact, stderr, status = compile_application(
          directory,
          ring: lower,
          source: source,
          basename: "nonempty-#{index}"
        )

        expect([status.exitstatus, assembly, artifact, stderr]).to eq [
          2,
          '',
          nil,
          "compiler: #{source_path}:1:0: error: " \
          "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
        ]
      end
    end
  end

  it 'does not broaden the allowance to a mixed upper source list' do
    Dir.mktmpdir('dab-modern-stdlib-ring-upper-list') do |directory|
      lower = build_stdlib(directory)
      legacy = File.join(directory, 'extra.dab')
      File.binwrite(legacy, ''.b)
      source, assembly, artifact, stderr, status = compile_application(
        directory,
        ring: lower,
        extra_inputs: [legacy]
      )

      expect([status.exitstatus, assembly, artifact, stderr]).to eq [
        2,
        '',
        nil,
        "compiler: #{source}:1:0: error: " \
        "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
      ]
    end
  end
end
