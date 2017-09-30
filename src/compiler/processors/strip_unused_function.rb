class StripUnusedFunction
  def run(node)
    return unless node.users.empty?
    return if $entry == node.identifier
    return if node.member_function?
    node.remove!
    true
  end
end
