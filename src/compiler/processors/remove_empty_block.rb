class RemoveEmptyBlock
  def run(node)
    return unless node.parent.is_a?(DabNodeCodeBlock)
    return unless node.empty?
    node.remove!
    true
  end
end
