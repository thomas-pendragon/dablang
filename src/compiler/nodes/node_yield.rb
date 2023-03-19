require_relative 'node_basecall'
require_relative '../processors/uncomplexify'

class DabNodeYield < DabNodeBasecall
  lower_with Uncomplexify

  def compile_as_ssa(output, output_register)
    list = args.map(&:register_string)
    output.printex(self, 'YIELD', output_register ? "R#{output_register}" : 'RNIL', *list)
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
