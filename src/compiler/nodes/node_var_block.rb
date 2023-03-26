require_relative 'node'

class DabNodeVarBlock < DabNodeBaseBlock
  early_after_init ExtractCallBlock

  def initialize(body, arglist = nil)
    super(body, arglist)
  end

  def has_block?
    true
  end

  def block
    self
  end
end
