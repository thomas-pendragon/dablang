require_relative 'node_basecall.rb'
require_relative '../processors/uncomplexify.rb'

class DabNodeYield < DabNodeBasecall
  lower_with Uncomplexify

  def compile(output)
    list = args.map(&:register_string)
    output.printex(self, 'Q_YIELD', *list)
  end

  def formatted_source(options)
    argstxt = if args.count > 0
                '(' + _formatted_arguments(options) + ')'
              else
                ''
              end
    'yield' + argstxt
  end

  def uncomplexify_args
    args
  end

  def accepts?(arg)
    arg.register?
  end
end
