class RemoveUnreachableBlock
  def run(node)
    return unless node.unreachable?
    node.remove!
    true
  end
end
