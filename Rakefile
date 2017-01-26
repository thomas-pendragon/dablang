def psystem(cmd)
  puts cmd
  unless system cmd
    raise 'error in cmd'
  end
end

def read_test_file(fname)
  text = ''
  test_body = ''
  mode = nil
  open(fname).read.split("\n").map(&:strip).each do |line|
    if line.start_with? '## '
      mode = line
    elsif mode == '## CODE'
      text += line + "\n"
    elsif mode == '## EXPECT OK'
      test_body += line + "\n"
    end
  end
  [text, test_body].map(&:strip)
end

inputs = Dir.glob('spec/input/*.dabt')
outputs = []
other_outputs = []
sources = Dir.glob('src/**/*.rb')

inputs.each do |input_test_file|
  input_file = input_test_file.gsub('spec/input', 'spec/output').gsub('.dabt', '.dab')
  output_file = input_file.gsub('.dab', '.dabca')
  output_binary_file = output_file.gsub('.dabca', '.dabcb')
  output_output_file = output_file.gsub('.dabca', '.out')
  outputs << output_output_file
  other_outputs << output_file
  other_outputs << output_binary_file
  other_outputs << input_file

  text, test_body = read_test_file(input_test_file)

  file input_file => sources + [input_test_file] do
    File.open(input_file, 'wb') { |f| f << text }
  end
  file output_file => sources + [input_file] do
    psystem("ruby src/compiler/compiler.rb < #{input_file} > #{output_file}")
  end
  file output_binary_file => sources + [output_file] do
    psystem("ruby src/tobinary/tobinary.rb < #{output_file} > #{output_binary_file}")
  end
  file output_output_file => sources + [input_test_file, output_binary_file] do
    psystem("ruby src/vm/vm.rb < #{output_binary_file} > #{output_output_file}")
    if open(output_output_file).read.strip == test_body
      puts "#{input_file}... OK"
    else
      puts "#{input_file}... Error"
      raise 'error'
    end
  end
end

task default: outputs do
end

task :clean do
  (outputs + other_outputs).each do |output_file|
    FileUtils.rm(output_file) if File.exist? output_file
  end
end
