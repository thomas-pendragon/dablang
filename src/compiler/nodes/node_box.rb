require_relative 'node'

class DabNodeBox < DabNode
  lower_with Uncomplexify

  def initialize(inner)
    super()
    insert(inner)
  end

  def value
    self[0]
  end

  def uncomplexify_args
    [value]
  end

  def compile_as_ssa(output, output_register)
    input_register = value.input_register
    output.printex(self, 'BOX', "R#{output_register}", "R#{input_register}")
  rescue StandardError
    puts ('!!' * 80).blue
    self.root.dump
    raise
  end
end
