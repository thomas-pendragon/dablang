require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

describe 'Dab Ruby tool versions' do
  project_root = File.expand_path('../..', __dir__)

  {
    'src/tobinary/tobinary.rb' => 'Dab assembler 0.0.2',
    'src/format/format.rb' => 'Dab formatter 0.0.2',
    'src/decompile/decompile.rb' => 'Dab decompiler 0.0.2',
    'src/cov/cov.rb' => 'Dab coverage 0.0.2',
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
