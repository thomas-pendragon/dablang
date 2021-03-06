require_relative 'node.rb'

class DabNodeSelf < DabNode
  def formatted_source(_options)
    'self'
  end

  def compile_as_ssa(output, output_register)
    output.print('LOAD_SELF', "R#{output_register}")
  end
end
