require_relative 'node'

class DabNodeBlockReference < DabNode
  def initialize(target)
    super()
    @target = target
    insert(@target.identifier)
  end

  def identifier
    self[0]
  end

  def real_identifier
    identifier.extra_value
  end

  def compile_as_ssa(output, output_register)
    output.printex(self, 'LOAD_METHOD', "R#{output_register}", identifier.symbol_arg)
  end
end
