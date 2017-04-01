require_relative 'src/shared/system.rb'
require 'colorize'
require 'yaml'

inputs = Dir.glob('test/dab/*.dabt').sort.reverse
outputs = []

format_inputs = Dir.glob('test/format/*.dabft').sort.reverse
format_outputs = []

sources = Dir.glob('src/**/*.rb')

makefile = 'build/Makefile'
premake = ENV['PREMAKE'] || 'premake5'
premake = "#{premake} gmake"
premake_source = 'premake5.lua'
cvm = 'bin/cvm'
cdisasm = 'bin/cdisasm'
filelist = 'tmp/c_files.txt'

cvm_opcodes = 'src/cshared/opcodes.h'
opcode_task = 'tasks/opcodelist.rb'

cvm_opcodes_debug = 'src/cshared/opcodes_debug.h'
opcode_debug_task = 'tasks/opcode_debuglist.rb'

shared_spec_code = Dir.glob('test/shared/*.dab')

csources = Dir.glob('src/{cvm,cshared,cdisasm}/**/*')
csources += [cvm_opcodes, cvm_opcodes_debug]
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

file cvm_opcodes_debug => ['src/shared/opcodes.rb', opcode_debug_task] do
  psystem("ruby #{opcode_debug_task} > #{cvm_opcodes_debug}")
end

file makefile => [premake_source, filelist] do
  psystem(premake.to_s)
end

file cdisasm => csources + [makefile] do
  Dir.chdir('build') do
    psystem('make cdisasm verbose=1')
  end
end

file cvm => csources + [makefile] do
  Dir.chdir('build') do
    psystem('make cvm verbose=1')
  end
end

inputs.each do |input_test_file|
  output_output_file = input_test_file.gsub('test/dab/', 'tmp/test_dab_').gsub('.dabt', '.out')
  outputs << output_output_file
  file output_output_file => sources + [input_test_file, cvm] + shared_spec_code do
    psystem("ruby src/frontend/frontend.rb #{input_test_file} --test_output_prefix test_dab_ --test_output_dir ./tmp/")
  end
end

format_inputs.each do |input_test_file|
  output_output_file = input_test_file.gsub('test/format/', 'tmp/test_format_').gsub('.dabft', '.out')
  format_outputs << output_output_file
  file output_output_file => sources + [input_test_file] do
    psystem("ruby src/frontend/frontend_format.rb #{input_test_file} --test_output_prefix test_format_ --test_output_dir ./tmp/")
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

task format_spec: format_outputs do
end

task reverse: outputs.reverse

task default: [gitlab] + [cvm] + [:spec] + [:format_spec] do
end

task :clean do
  files = Dir.glob('./tmp/**/*') + Dir.glob('./bin/**/') + Dir.glob('./build/**/*')
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
  psystem('git checkout master; git merge develop; git multipush github; git checkout develop')
end

task :dev do
  psystem('git checkout develop; git multipush origin --force')
end
