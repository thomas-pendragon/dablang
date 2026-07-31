require 'spec_helper'

require 'open3'
require 'rbconfig'

describe 'tracked generated documentation' do
  let(:root) { File.expand_path('..', __dir__) }

  def run_generator(relative_path)
    Open3.capture3(RbConfig.ruby, relative_path, chdir: root)
  end

  def normalize_newlines(value)
    value.gsub("\r\n", "\n")
  end

  it 'generates opcode documentation independently of source mtime' do
    source = File.join(root, 'src/shared/opcodes.rb')
    tracked_output = File.binread(File.join(root, 'docs/vm/opcodes.md'))
    original_stat = File.stat(source)

    begin
      first_stdout, first_stderr, first_status = run_generator('tasks/opcode_docs.rb')
      File.utime(original_stat.atime, Time.utc(2001, 2, 3, 4, 5, 6), source)
      second_stdout, second_stderr, second_status = run_generator('tasks/opcode_docs.rb')

      expect(first_status).to be_success, first_stderr
      expect(second_status).to be_success, second_stderr
      expect(normalize_newlines(first_stdout.b)).to eq(normalize_newlines(tracked_output))
      expect(normalize_newlines(second_stdout.b)).to eq(normalize_newlines(first_stdout.b))
    ensure
      File.utime(original_stat.atime, original_stat.mtime, source)
    end
  end

  it 'regenerates the tracked class index and pages without changing their contents' do
    source = File.join(root, 'src/shared/classes.rb')
    original_stat = File.stat(source)
    generated_paths = [File.join(root, 'docs/classes.md')] + Dir[File.join(root, 'docs/classes/*.md')].sort
    tracked_outputs = generated_paths.to_h do |path|
      [path, normalize_newlines(File.binread(path))]
    end

    begin
      _first_stdout, first_stderr, first_status = run_generator('tasks/classes_docs.rb')
      File.utime(original_stat.atime, Time.utc(2001, 2, 3, 4, 5, 6), source)
      _second_stdout, second_stderr, second_status = run_generator('tasks/classes_docs.rb')

      expect(first_status).to be_success, first_stderr
      expect(second_status).to be_success, second_stderr
      regenerated_outputs = generated_paths.to_h do |path|
        [path, normalize_newlines(File.binread(path))]
      end
      expect(regenerated_outputs).to eq(tracked_outputs)
    ensure
      File.utime(original_stat.atime, original_stat.mtime, source)
    end
  end
end
