require_relative '../../setup.rb'
require_relative '../shared/debug_output.rb'
require_relative '../shared/args.rb'
require_relative '../shared/system.rb'
require_relative '../frontend/shared_noautorun.rb'

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

class CovFrontend
  include BaseFrontend

  def run(input, format, options)
    if input.end_with? '.dab'
      target = input.gsub(/\.dab$/, '.dabca')
      compile_dab_to_asm(input, target, "#{options} --with-cov")
      input = target
    end

    if input.end_with? '.dabca'
      target = input.gsub(/\.dabca$/, '.dabcb')
      assemble(input, target, options)
      input = target
    end

    unless input.end_with? '.dabcb'
      raise 'expected .dabcb file'
    end

    vm_cov_target = input.gsub(/\.dabcb$/, '.vm_cov')
    qsystem("./bin/cvm #{options} --cov #{input}", output_file: vm_cov_target)

    dump_cov_target = input.gsub(/\.dabcb$/, '.dump_cov')
    qsystem("./bin/cdumpcov #{options} #{input}", output_file: dump_cov_target)

    dump = JSON.parse(File.read(dump_cov_target))
    vm = JSON.parse(File.read(vm_cov_target))

    files = dump.map { |item| item['file'] }

    if %w[plaintext text].include?(format)
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
  end
end

input = $settings[:input]
format = $settings[:format] || 'text'
options = ''

CovFrontend.new.run(input, format, options)
