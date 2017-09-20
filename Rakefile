require_relative 'setup.rb'
require_relative 'src/shared/system.rb'

$autorun = false

require_relative './src/frontend/frontend.rb'
require_relative './src/frontend/frontend_asm.rb'

$sources = Dir.glob('src/**/*.rb')

makefile = 'build/Makefile'
premake = ENV['PREMAKE'] || 'premake5'
premake = "#{premake} gmake"
premake_source = 'premake5.lua'
cvm = 'bin/cvm'
cdisasm = 'bin/cdisasm'
cdumpcov = 'bin/cdumpcov'
filelist = 'tmp/c_files.txt'

opcodes = 'src/shared/opcodes.rb'
classes_file = 'src/shared/classes.rb'

cvm_opcodes = 'src/cshared/opcodes.h'
cvm_classes = 'src/cshared/classes.h'
opcode_task = 'tasks/opcodelist.rb'
classes_task = 'tasks/classes.rb'

cvm_opcodes_debug = 'src/cshared/opcodes_debug.h'
opcode_debug_task = 'tasks/opcode_debuglist.rb'

opcode_docs_file = 'docs/vm/opcodes.md'
opcode_docs_task = 'tasks/opcode_docs.rb'

classes_docs_file = './docs/classes.md'
classes_docs_task = './tasks/classes_docs.rb'

ffi_file = './src/cvm/ffi_signatures.h'
ffi_task = './tasks/ffi_signatures.rb'

$shared_spec_code = Dir.glob('test/shared/*.dab')

csources = Dir.glob('src/{cvm,cshared,cdisasm,cdumpcov}/**/*')
csources += [cvm_opcodes, cvm_classes, cvm_opcodes_debug]
csources.sort!
csources.uniq!

filelist_body_new = csources.join("\n")
filelist_body_old = open(filelist).read.strip rescue nil
if filelist_body_old != filelist_body_new
  puts "Warning! Updating #{filelist}.".bold.yellow
  File.open(filelist, 'wb') { |f| f << filelist_body_new }
end

file cvm_classes => [opcodes, classes_task] do
  psystem("ruby #{classes_task} > #{cvm_classes}")
end

file cvm_opcodes => [opcodes, opcode_task] do
  psystem("ruby #{opcode_task} > #{cvm_opcodes}")
end

file cvm_opcodes_debug => [opcodes, opcode_debug_task] do
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

file cvm => csources + [makefile, ffi_file] do
  Dir.chdir('build') do
    psystem('make cvm verbose=1')
  end
end

file cdumpcov => csources + [makefile] do
  Dir.chdir('build') do
    psystem('make cdumpcov verbose=1')
  end
end

def ci_parallel(inputs)
  ci_index = ENV['CI_PARALLEL_INDEX']&.to_i
  ci_total = ENV['CI_PARALLEL_TOTAL']&.to_i
  return inputs unless ci_index && ci_total
  per_instance = (inputs.count.to_f / ci_total.to_f).ceil.to_i
  istart = ci_index * per_instance
  iend = (ci_index + 1) * per_instance
  inputs[istart...iend] || []
end

def setup_tests(directory, extension = 'test', frontend_type = nil, extras = [], test_name = nil, direct_run = nil)
  test_name ||= "#{directory}_spec"
  frontend_type ||= "frontend_#{directory}"
  base_path = 'test/' + directory
  path = base_path + '/*.' + extension
  test_file_name = 'test_' + test_name + '_'
  inputs = Dir.glob(path).sort.reverse
  inputs = ci_parallel(inputs)
  outputs = []
  inputs.each do |input_test_file|
    output_output_file = input_test_file.gsub(base_path + '/', 'tmp/' + test_file_name).gsub('.' + extension, '.out')
    outputs << output_output_file
    inputs = $sources + [input_test_file] + $shared_spec_code + extras
    file output_output_file => inputs do
      puts '>> '.white + output_output_file.white.bold
      if direct_run.nil?
        psystem("ruby src/frontend/#{frontend_type}.rb #{input_test_file} --test_output_prefix=#{test_file_name} --test_output_dir=./tmp/")
      else
        settings = {
          input: input_test_file,
          inputs: [input_test_file],
          test_output_prefix: test_file_name,
          test_output_dir: './tmp/',
        }
        direct_run.new.run_test(settings)
      end
    end
  end
  task test_name.to_sym => outputs
  task "#{test_name}_reverse".to_sym => outputs.reverse
end

setup_tests('dab', 'dabt', 'frontend', [cvm], 'dab', DabSpec)
setup_tests('format', 'dabft', 'frontend_format')
setup_tests('vm', 'vmt', 'frontend_vm', [cvm])
setup_tests('disasm', 'dat', 'frontend_disasm', [cdisasm])
setup_tests('asm', 'asmt', 'frontend_asm', [], nil, AsmSpec)
setup_tests('dumpcov', 'test', 'frontend_dumpcov', [cdumpcov])
setup_tests('cov', 'test', 'frontend_cov', [cvm, cdumpcov])
setup_tests('debug', 'test', 'frontend_debug', [cvm])
setup_tests('decompile')
setup_tests('compiler_performance')
setup_tests('../examples', 'dab', 'frontend_build_example', [], 'build_examples_spec')

gitlab = '.gitlab-ci.yml'
gitlab_base = 'gitlab_base.rb'

file gitlab => [gitlab_base, 'gitlab_base.yml'] do
  psystem("ruby #{gitlab_base} > #{gitlab}")
end

task :docker do
  tag = YAML.load_file('gitlab_base.yml')['image']
  psystem("cd dockerenv && docker build -t #{tag} . && docker push #{tag}")
end

task spec: :dab do
end

task reverse: :dab_reverse

file opcode_docs_file => [opcodes, opcode_docs_task] do
  psystem("ruby #{opcode_docs_task} > #{opcode_docs_file}")
end

file classes_docs_file => [classes_file, classes_docs_task] do
  psystem("ruby #{classes_docs_task}")
end

file ffi_file => [ffi_task] do
  psystem("ruby #{ffi_task} > #{ffi_file}")
end

task default: [gitlab, opcode_docs_file, classes_docs_file, cvm, cdisasm, :spec, :format_spec, :vm_spec, :disasm_spec,
               :asm_spec, :dumpcov_spec, :cov_spec, :debug_spec, :build_examples_spec] do
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
    psystem('bundle exec rubocop >/dev/null 2>/dev/null || bundle exec rubocop -a')
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

  task stdlib: $sources do
    files = Dir.glob('./stdlib/**/*.dab')
    files.each do |file|
      psystem("ruby src/format/format.rb < #{file} > #{file}.format; mv #{file}.format #{file}")
    end
  end

  task stdlib_check: $sources do
    files = Dir.glob('./stdlib/**/*.dab')
    files.each do |file|
      psystem("ruby src/format/format.rb < #{file} | diff #{file} -")
    end
  end

  task :sort do
    psystem('ruby ./tasks/sort.rb')
  end

  task :sort_check do
    psystem('ruby ./tasks/sort.rb --check')
  end

  task :sortfiles_check do
    psystem('ruby ./tasks/sortfiles.rb')
  end
end

task format: ['format:sort', 'format:ruby', 'format:cpp']

task :master do
  psystem('git multipush github master; git branch -f master github/master')
end

task :dev do
  psystem('git multipush origin master --force')
end

task :example, [:number] => [cvm] do |_t, args|
  number = args[:number]
  input = Dir.glob(sprintf('examples/%04d*', number)).first
  psystem("ruby src/frontend/frontend_example.rb #{input}")
end

task :benchmark do
  psystem("git-benchmark performance-base..HEAD 'ruby src/compiler/compiler.rb tmp/test_compiler_performance_0001_random.dab'")
end
