require_relative 'node_base_block'

class DabNodeCallBlock < DabNodeBaseBlock
  def initialize(body, arglist = nil)
    super
  end

  def formatted_source(options)
    " #{super}"
  end
end
