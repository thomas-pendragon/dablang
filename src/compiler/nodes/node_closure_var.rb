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
    output.print('Q_RELEASE', "R#{output_register}") if $no_autorelease
    output.print('Q_SET_CLOSURE', "R#{output_register}", index)
  end
end
