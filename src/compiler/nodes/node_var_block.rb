require_relative 'node'

class DabNodeVarBlock < DabNodeBaseBlock
  after_init ExtractCallBlock

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

class DabNodeLocalBlock < DabNode
  def initialize(inner)
    super()
    insert(inner)
  end
end
