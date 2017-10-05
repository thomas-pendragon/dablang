require_relative 'node_literal.rb'

class DabNodeLiteralNil < DabNodeLiteral
  def compile(output)
    output.print('PUSH_NIL')
  end

  def compile_as_ssa(output, output_register)
    output.printex(self, 'Q_SET_NIL', "R#{output_register}")
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
