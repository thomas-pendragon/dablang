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

  def with_source(source)
    Dir.mktmpdir('dab-compiler-syntax-option') do |directory|
      path = File.join(directory, 'program.dab')
      File.binwrite(path, source)
      yield path
    end
  end

  it 'resolves explicit legacy to the canonical profile and removes only its option' do
    syntax_profile, arguments = DabCompilerSyntaxOptions.parse(['source.dab', '--syntax=legacy', '--no-opt'])

    expect(syntax_profile).to equal(DabSyntaxProfile::LEGACY)
    expect(arguments).to eq ['source.dab', '--no-opt']
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

  it 'fails closed for unregistered and empty profiles' do
    {
      '--syntax=modern' => 'compiler: unknown Dab syntax profile "modern"; available profiles: legacy',
      '--syntax=' => 'compiler: unknown Dab syntax profile ""; available profiles: legacy',
    }.each do |argument, diagnostic|
      stdout, stderr, status = invoke(argument)

      expect([stdout, stderr, status.exitstatus]).to eq ['', "#{diagnostic}\n", 2]
    end
  end

  it 'rejects malformed, separated, and repeated syntax options before inputs' do
    {
      ['--syntax'] => 'compiler: --syntax requires the --syntax=PROFILE spelling',
      ['--syntax', 'legacy'] => 'compiler: --syntax requires the --syntax=PROFILE spelling',
      ['--syntax=legacy', '--syntax=legacy'] => 'compiler: --syntax may be specified at most once',
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
