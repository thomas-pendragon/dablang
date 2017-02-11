require_relative 'src/shared/system.rb'

inputs = Dir.glob('spec/input/*.dabt').sort.reverse
outputs = []
sources = Dir.glob('src/**/*.rb')

cvm_sources = Dir.glob('src/cvm/*.cpp')
cvm = 'bin/cvm'

file cvm => cvm_sources do
  compiler = ENV['COMPILER'] || 'clang++'
  cxxflags = ENV['CXXFLAGS'] || ''
  psystem("#{compiler} -std=c++11 #{cvm_sources.join(' ')} #{cxxflags} -o #{cvm}")
end

inputs.each do |input_test_file|
  output_output_file = input_test_file.gsub('/input/', '/output/').gsub('.dabt', '.out')
  outputs << output_output_file
  file output_output_file => sources + [input_test_file, cvm] do
    psystem("ruby src/frontend/frontend.rb #{input_test_file} --test_output_dir ./spec/output/")
  end
end

task default: [cvm] + outputs do
end

task :clean do
  (Dir.glob('./spec/output/*') + Dir.glob('./bin/*')).each do |file|
    next if file == '.gitkeep'
    FileUtils.rm(file)
  end
end

namespace :format do
  task :ruby do
    psystem('rubocop -a')
  end

  task :cpp do
    files = (%w(cpp mm m h).map { |ext| Dir.glob("src/**/*.#{ext}") }).flatten(1)
    files.each do |file|
      psystem("clang-format -i #{file}")
    end
  end
end

task format: ['format:ruby', 'format:cpp']
