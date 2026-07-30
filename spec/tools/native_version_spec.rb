require 'spec_helper'

require 'open3'
require 'tmpdir'

describe 'Dab native tool versions' do
  project_root = File.expand_path('../..', __dir__)
  project_version = File.read(File.join(project_root, 'VERSION')).strip

  {
    'bin/cvm' => "Dab VM #{project_version}",
    'bin/cdisasm' => "Dab disassembler #{project_version}",
    'bin/cdumpcov' => "Dab coverage dumper #{project_version}",
  }.each do |relative_path, expected_output|
    it "reports #{expected_output}" do
      Dir.mktmpdir('dab-native-tool-version') do |directory|
        stdout, stderr, status = Open3.capture3(
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
