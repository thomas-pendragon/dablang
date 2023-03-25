class DabNodeCurrentBlock < DabNode
  def compile_as_ssa(output, output_register)
    output.printex(self, 'LOAD_CURRENT_BLOCK', "R#{output_register}")
  end
end
