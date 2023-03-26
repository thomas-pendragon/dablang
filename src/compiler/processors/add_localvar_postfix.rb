class AddLocalvarPostfix
  def run(node)
    errap ['AddLocalvarPostfix', node, 'source', node.source_file, node.source_line, 'parent', node.parent]
    node.root.dump

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
