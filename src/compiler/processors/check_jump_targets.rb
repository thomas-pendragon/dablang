class CheckJumpTargets
  def run(node)
    all_targets = node.function.all_nodes(DabNodeCodeBlockEx)
    node.targets.each do |target|
      unless all_targets.include?(target)
        raise 'internal compiler error: invalid jump'
      end
    end
    false
  end
end
