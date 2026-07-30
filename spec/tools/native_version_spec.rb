require 'spec_helper'

require 'open3'
require 'tmpdir'

describe 'Dab native tool versions' do
  project_root = File.expand_path('../..', __dir__)

  {
    'bin/cvm' => 'Dab VM 0.0.2',
    'bin/cdisasm' => 'Dab disassembler 0.0.2',
    'bin/cdumpcov' => 'Dab coverage dumper 0.0.2',
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
