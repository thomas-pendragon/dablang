class StripUnusedFunction
  def run(node)
    return unless node.users.empty?
    return if $entry == node.identifier
    node.remove!
    true
  end
end
