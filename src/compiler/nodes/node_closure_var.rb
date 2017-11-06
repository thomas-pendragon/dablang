require_relative 'node.rb'

class DabNodeClosureVar < DabNode
  attr_reader :index

  def initialize(index)
    super()
    @index = index
  end

  def extra_dump
    "&#{index}"
  end

  def compile_as_ssa(output, output_register)
    output.print('LOAD_CLOSURE', "R#{output_register}", index)
  end
end
