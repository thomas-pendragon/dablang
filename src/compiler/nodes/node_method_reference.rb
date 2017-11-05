require_relative 'node.rb'

class DabNodeMethodReference < DabNode
  attr_reader :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
    insert(@identifier)
  end

  def node_identifier
    self[0]
  end

  def compile_as_ssa(output, output_register)
    output.printex(self, 'LOAD_METHOD', "R#{output_register}", node_identifier.symbol_arg)
  end
end
