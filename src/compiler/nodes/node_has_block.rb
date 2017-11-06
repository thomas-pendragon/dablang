require_relative 'node.rb'

class DabNodeHasBlock < DabNode
  def compile_as_ssa(output, output_register)
    output.printex(self, 'LOAD_HAS_BLOCK', "R#{output_register}")
  end
end
