require_relative 'node_basecall'
require_relative '../processors/uncomplexify'

class DabNodeYield < DabNodeBasecall
  # lower_with Uncomplexify
  after_init :yield_to_call

  def compile_as_ssa(output, output_register)
    list = args.map(&:register_string)
    output.printex(self, 'YIELD', output_register ? "R#{output_register}" : 'RNIL', *list)
  end

  def formatted_source(options)
    argstxt = if args.count > 0
                "(#{_formatted_arguments(options)})"
              else
                ''
              end
    "yield#{argstxt}"
  end

  def uncomplexify_args
    args
  end

  def accepts?(arg)
    arg.register?
  end

  def yield_to_call
    node = self
    # def initialize(value, identifier, arglist, block)
    arglist = node.args
    call = DabNodeInstanceCall.new(DabNodeCurrentBlock.new, :call, arglist, nil)
    node.replace_with!(call)
  end
end
