require_relative 'node'

class DabNodeBox < DabNode
  # lower_with Uncomplexify
  lower_with :ssa_box

  def initialize(inner)
    super()
    insert(inner)
  end

  def value
    self[0]
  end

  # def uncomplexify_args
  #   [value]
  # end

  def compile_as_ssa(output, output_register)
    input_register = value.input_register
    output.printex(self, 'BOX', "R#{output_register}", "R#{input_register}")
  rescue StandardError
    puts ('!!' * 80).blue
    self.root.dump
    raise
  end

  def ssa_box
    # raise 'SSA BOX'

    return if @ssa_box

    err ('^' * 80).blue
    self.dump

    @ssa_box = true

    node = self
    complex_arg = value

    id = node.function.allocate_tempvar
    arg_dup = complex_arg.dup
    reg = node.function.allocate_ssa
    setter = DabNodeSSASet.new(arg_dup, reg, id)
    getter = DabNodeSSAGet.new(reg, id)
    node.prepend_instruction(setter)
    complex_arg.replace_with!(getter)

    err ('^' * 80).yellow
    self.dump

    err ('^' * 80).red

    true
  end
end

class DabNodeSetbox < DabNodeBox
  def initialize(inner, localvar)
    super(inner)
    insert(localvar)
  end

  def localvar
    self[1]
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
