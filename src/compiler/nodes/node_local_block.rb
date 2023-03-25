require_relative 'node'

class DabNodeLocalBlock < DabNode
  def initialize(inner)
    super()
    insert(inner)
  end

  def block
    self[0]
  end

  def compile_as_ssa(output, output_register)
    output.printex(self, 'MARK_LOCAL_BLOCK', "R#{output_register}", "R#{block.input_register}")
  end

  def count_as_argument?
    false
  end
end
