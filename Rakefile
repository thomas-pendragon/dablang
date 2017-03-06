require_relative 'src/shared/system.rb'
require 'colorize'
require 'yaml'

inputs = Dir.glob('spec/input/*.dabt').sort.reverse
outputs = []
sources = Dir.glob('src/**/*.rb')

makefile = 'build/Makefile'
premake = ENV['PREMAKE'] || 'premake5'
premake = "#{premake} gmake"
premake_source = 'premake5.lua'
cvm = 'bin/cvm'
filelist = 'tmp/c_files.txt'

cvm_opcodes = 'src/cvm/opcodes.h'
opcode_task = 'tasks/opcodelist.rb'

csources = Dir.glob('src/cvm/**/*')
csources += [cvm_opcodes]
csources.sort!
csources.uniq!

filelist_body_new = csources.join("\n")
filelist_body_old = open(filelist).read.strip rescue nil
if filelist_body_old != filelist_body_new
  puts "Warning! Updating #{filelist}.".bold.yellow
  File.open(filelist, 'wb') { |f| f << filelist_body_new }
end

file cvm_opcodes => ['src/shared/opcodes.rb', opcode_task] do
  psystem("ruby #{opcode_task} > #{cvm_opcodes}")
end

file makefile => [premake_source, filelist] do
  psystem(premake.to_s)
end

file cvm => csources + [makefile] do
  Dir.chdir('build') do
    psystem('make cvm verbose=1')
  end
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

file gitlab => [gitlab_base, 'gitlab_base.yml'] do
  psystem("ruby #{gitlab_base} > #{gitlab}")
end

task :docker do
  tag = YAML.load_file('gitlab_base.yml')['image']
  psystem("cd dockerenv && docker build -t #{tag} . && docker push #{tag}")
end

task spec: outputs do
end

task default: [gitlab] + [cvm] + [:spec] do
end

task :clean do
  files = Dir.glob('./spec/output/**/*') + Dir.glob('./bin/**/') + Dir.glob('./build/**/*')
  files.each do |file|
    next if file == '.gitkeep'
    if File.file?(file)
      puts "> Remove file #{file}"
      FileUtils.rm(file)
    end
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
    psystem('rubocop >/dev/null 2>/dev/null || rubocop -a')
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

  task :sort do
    psystem('ruby ./tasks/sort.rb')
  end

  task :sort_check do
    psystem('ruby ./tasks/sort.rb --check')
  end
end

task format: ['format:sort', 'format:ruby', 'format:cpp']

task :master do
  psystem('git checkout master; git merge develop; git multipush; git checkout develop')
end

task :dev do
  psystem('git checkout develop; git multipush gitlab master --force')
end
