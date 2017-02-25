require_relative 'src/shared/system.rb'

inputs = Dir.glob('spec/input/*.dabt').sort.reverse
outputs = []
sources = Dir.glob('src/**/*.rb')

cvm_sources = Dir.glob('src/cvm/*.cpp')
cvm_headers = Dir.glob('src/cvm/*.h')
cvm = 'bin/cvm'

file cvm => cvm_sources + cvm_headers do
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

gitlab = '.gitlab-ci.yml'
gitlab_base = 'gitlab_base.rb'

file gitlab => [gitlab_base] do
  psystem("ruby #{gitlab_base} > #{gitlab}")
end

task spec: outputs do
end

task default: [gitlab] + [cvm] + [:spec] do
end

task :clean do
  (Dir.glob('./spec/output/*') + Dir.glob('./bin/*')).each do |file|
    next if file == '.gitkeep'
    FileUtils.rm(file)
  end
end

def cpp_check
  files = (%w(cpp mm m h).map { |ext| Dir.glob("src/**/*.#{ext}") }).flatten(1)
  files.each do |file|
    yield(file)
  end
end

namespace :format do
  task :ruby do
    psystem('rubocop -a')
  end

  task :cpp do
    cpp_check do |file|
      psystem("clang-format -i #{file}")
    end
  end

  task :cpp_check do
    cpp_check do |file|
      psystem("clang-format #{file} | diff #{file} -")
    end
  end
end

task format: ['format:ruby', 'format:cpp']
