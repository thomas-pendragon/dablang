require_relative 'node_var_block.rb'

class DabNodeCallBlock < DabNodeVarBlock
  def initialize(body, arglist = nil)
    super(body, arglist)
  end

  def formatted_source(options)
    ' ' + super(options)
  end
end
