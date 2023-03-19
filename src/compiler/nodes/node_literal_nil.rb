require_relative 'node_literal'

class DabNodeLiteralNil < DabNodeLiteral
  def compile_as_ssa(output, output_register)
    output.printex(self, 'LOAD_NIL', "R#{output_register}")
  end

  def my_type
    DabTypeNil.new
  end

  def constant_value
    nil
  end

  def formatted_source(_)
    'nil'
  end

  def literal_nil?
    true
  end

  def register_string
    'RNIL'
  end

  def cast_to(_target_type)
    self
  end
end
