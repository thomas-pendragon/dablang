require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

describe 'Dab Ruby tool versions' do
  project_root = File.expand_path('../..', __dir__)
  project_version = File.read(File.join(project_root, 'VERSION')).strip

  {
    'src/tobinary/tobinary.rb' => "Dab assembler #{project_version}",
    'src/format/format.rb' => "Dab formatter #{project_version}",
    'src/decompile/decompile.rb' => "Dab decompiler #{project_version}",
    'src/cov/cov.rb' => "Dab coverage #{project_version}",
  }.each do |relative_path, expected_output|
    it "reports #{expected_output}" do
      Dir.mktmpdir('dab-ruby-tool-version') do |directory|
        stdout, stderr, status = Open3.capture3(
          RbConfig.ruby,
          File.join(project_root, relative_path),
          '--version',
          chdir: directory,
          stdin_data: 'ignored input'
        )

        expect(stdout).to eq("#{expected_output}\n")
        expect(stderr).to eq('')
        expect(status).to be_success
        expect(Dir.entries(directory) - %w[. ..]).to be_empty
      end
    end
  end
end
