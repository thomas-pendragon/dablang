require_relative 'src/shared/system.rb'

inputs = Dir.glob('spec/input/*.dabt')
outputs = []
sources = Dir.glob('src/**/*.rb')

inputs.each do |input_test_file|
  output_output_file = input_test_file.gsub('/input/', '/output/').gsub('.dabt', '.out')
  outputs << output_output_file
  file output_output_file => sources + [input_test_file] do
    psystem("ruby src/frontend/frontend.rb #{input_test_file} --test_output_dir ./spec/output/")
  end
end

task default: outputs do
end

task :clean do
  Dir.glob('./spec/output/*').each do |file|
    next if file == '.gitkeep'
    FileUtils.rm(file)
  end
end
