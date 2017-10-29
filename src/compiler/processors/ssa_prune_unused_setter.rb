class SSAPruneUnusedSetter
  def run(node)
    return if node.users.count > 0
    if node.value.is_a? DabNodeSSAPhi
      node.remove!
    else
      node.replace_with!(node.value.dup)
    end
    true
  end
end
