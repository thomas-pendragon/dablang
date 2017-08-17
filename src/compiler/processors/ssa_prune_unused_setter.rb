class SSAPruneUnusedSetter
  def run(node)
    return if node.users.count > 0
    node.remove! # TODO: side-effects check
    true
  end
end
