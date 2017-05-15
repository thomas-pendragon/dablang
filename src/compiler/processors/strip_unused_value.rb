class StripUnusedValue
  def run(node)
    return unless node.parent.is_a? DabNodeCodeBlock
    node.remove!
    true
  end
end
