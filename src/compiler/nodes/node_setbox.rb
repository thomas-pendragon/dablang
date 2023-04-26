require_relative 'node_box'

class DabNodeSetbox < DabNodeBox
  def initialize(inner, localvar)
    super(inner)
    insert(localvar)
  end

  def localvar
    self[1]
  end

  def protected_registers
    [localvar.input_register]
  end

  def fixup_protected_arg(old:, new:)
    localvar.input_register = new
  end

  def compile_as_ssa(output, output_register)
    new_input_register = value.input_register
    var_input_register = localvar.input_register

    output.printex(self, 'SETBOX',
                   output_register.nil? ? 'RNIL' : "R#{output_register}",
                   "R#{var_input_register}",
                   "R#{new_input_register}")
  end
end
