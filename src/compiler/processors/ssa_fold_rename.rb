class SSAFoldRename
  def run(node)
    return unless node.value.is_a?(DabNodeSSAGet)
    source = node.value.input_register
    node.users.each do |user|
      user.input_register = source
    end
    node.remove!
    true
  end
end
