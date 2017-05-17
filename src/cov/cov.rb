require_relative '../../setup.rb'
require_relative '../shared/debug_output.rb'
require_relative '../shared/args.rb'
require_relative '../shared/system.rb'

input = $settings[:input]
format = $settings[:format] || 'text'

if input.end_with? '.dab'
  target = input.gsub(/\.dab$/, '.dabca')
  psystem "ruby ./src/compiler/compiler.rb #{input} --with-cov > #{target} 2> /dev/null"
  input = target
end

if input.end_with? '.dabca'
  target = input.gsub(/\.dabca$/, '.dabcb')
  psystem "ruby ./src/tobinary/tobinary.rb < #{input} > #{target} 2> /dev/null"
  input = target
end

unless input.end_with? '.dabcb'
  raise 'expected .dabcb file'
end

vm_cov_target = input.gsub(/\.dabcb$/, '.vm_cov')
psystem "./bin/cvm --cov #{input} > #{vm_cov_target}"

dump_cov_target = input.gsub(/\.dabcb$/, '.dump_cov')
psystem "./bin/cdumpcov < #{input} > #{dump_cov_target}"

dump = JSON.parse(File.read(dump_cov_target))
vm = JSON.parse(File.read(vm_cov_target))

files = dump.map { |item| item['file'] }

class String
  def covformat(format, methods)
    methods = [methods] unless methods.is_a? Array
    ret = self
    if format == 'text'
      methods.each do |method|
        ret = ret.send(method)
      end
    end
    ret
  end
end

if format == 'plaintext' || format == 'text'
  files.each do |file|
    data = vm.detect { |item| item['file'] == file }
    raise "no data for #{file}" unless data
    data = data['hits']
    data = data.map { |item| [item['line'], item['hits']] }.to_h

    set = dump.detect { |item| item['file'] == file }['lines']

    puts file.covformat(format, :bold)
    puts
    lines = File.read(file).lines
    lines.each_with_index do |line, index|
      index += 1
      included = set.include?(index)
      str = sprintf('%5d: %s', index, line)
      hits = data[index] || 0
      str = if included && hits > 0
              str = sprintf('%5d hit%s ', hits, hits > 1 ? 's' : ' ') + str
              str.covformat(format, %i(green bold))
            elsif included
              str = '     miss  ' + str
              str.covformat(format, %i(red bold))
            else
              ' ' * 11 + str.covformat(format, :white)
            end
      print str
    end
  end
end
