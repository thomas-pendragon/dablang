require_relative 'node.rb'

class DabNodeSelf < DabNode
  def compile(output)
    output.print('PUSH_SELF')
  end

  def formatted_source(_options)
    'self'
  end

  def compile_as_ssa(output, output_register)
    output.print('Q_SET_SELF', "R#{output_register}")
  end
end
