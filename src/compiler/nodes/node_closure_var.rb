require_relative 'node'

class DabNodeClosureVar < DabNode
  attr_reader :index

  lower_with :to_instvar

  def initialize(index)
    super()
    @index = index
  end

  def extra_dump
    "&#{index}"
  end

  # def compile_as_ssa(output, output_register)
  #   output.print('LOAD_CLOSURE', "R#{output_register}", index)
  # end

  def to_instvar
    data = DabNodeInstanceVar.new('@closure')
    lindex = DabNodeLiteralNumber.new(@index)
    op = DabNodeInstanceCall.new(data, '[]', [lindex], nil)
    replace_with!(op)
    true
  end
end
