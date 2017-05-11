class CheckJumpTargets
  def run(node)
    all_targets = node.function.all_nodes(DabNodeCodeBlockEx)
    node.targets.each do |target|
      next if all_targets.include?(target)
      node.function.dump
      err '--~' * 50
      node.dump
      raise 'internal compiler error: invalid jump'
    end
    false
  end
end
