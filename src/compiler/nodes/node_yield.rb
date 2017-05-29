require_relative 'node_basecall.rb'

class DabNodeYield < DabNodeBasecall
  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.printex(self, 'YIELD', args.count)
  end

  def formatted_source(options)
    argstxt = if args.count > 0
                '(' + _formatted_arguments(options) + ')'
              else
                ''
              end
    'yield' + argstxt + ';'
  end
end
