require_relative 'node.rb'

class DabNodeBaseJump < DabNode
  def replace_target!(_from, _to)
    raise 'must implement'
  end
end
