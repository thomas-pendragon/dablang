require_relative 'node_base_block'

class DabNodeCallBlock < DabNodeBaseBlock
  def initialize(body, arglist = nil)
    super(body, arglist)
  end

  def formatted_source(options)
    " #{super(options)}"
  end
end
