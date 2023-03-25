require_relative 'node_basecall'
require_relative '../processors/uncomplexify'

class DabNodeYield < DabNodeBasecall
  # lower_with Uncomplexify
  after_init :yield_to_call

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
    arglist = self.args
    call = DabNodeInstanceCall.new(DabNodeCurrentBlock.new, :call, arglist, nil)
    self.replace_with!(call)
  end
end
