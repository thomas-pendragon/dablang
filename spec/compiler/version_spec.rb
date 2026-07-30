require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

describe 'Dab compiler version' do
  let(:project_root) { File.expand_path('../..', __dir__) }
  let(:version_file) { File.join(project_root, 'VERSION') }
  let(:compiler) { File.join(project_root, 'src/compiler/compiler.rb') }

  it 'records the project version in the root VERSION file' do
    expect(File.read(version_file)).to eq("0.0.2\n")
  end

  it 'prints the exact version and exits successfully without input or artifacts' do
    Dir.mktmpdir('dab-compiler-version') do |directory|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        compiler,
        '--version',
        chdir: directory,
        stdin_data: 'ignored input'
      )

      expect(stdout).to eq("Dab compiler 0.0.2\n")
      expect(stderr).to eq('')
      expect(status).to be_success
      expect(Dir.entries(directory) - %w[. ..]).to be_empty
    end
  end
end
