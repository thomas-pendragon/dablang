class AddLocalvarPostfix
  def run(node)
    return if node.identifier['#']

    fun_index = 1
    while true
      new_id = "#{node.identifier}##{fun_index}"
      break unless node.function.all_nodes(DabNodeDefineLocalVar).detect { |vdef| vdef.identifier == new_id }

      fun_index += 1
    end

    node.all_users.each do |user|
      user.identifier = new_id
    end

    true
  end
end
