class RemoveUnreachableBlock
  def run(node)
    return if node.embedded?
    return unless node.unreachable?
    node.remove!
    true
  end
end
