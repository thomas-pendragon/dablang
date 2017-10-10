require_relative 'node.rb'

class DabNodeHasBlock < DabNode
  def compile_as_ssa(output, output_register)
    output.printex(self, 'Q_SET_HAS_BLOCK', "R#{output_register}")
  end
end
