require_relative 'node'
require_relative '../processors/check_jump_targets'

class DabNodeBaseJump < DabNode
  check_with CheckJumpTargets

  def replace_target!(_from, _to)
    raise 'must implement'
  end

  def targets
    raise 'must implement'
  end

  def returns_value?
    false
  end
end
