class AddLocalvarPostfix
  def run(node)
    xx = node.function.identifier == 'call'
    if xx
      errap ['AddLocalvarPostfix', node, 'source', node.source_file, node.source_line, 'parent', node.function.identifier]
      node.function.dump
      err '-' * 80
    end

    return if node.identifier['#']

    fun_index = 1
    while true
      new_id = "#{node.identifier}##{fun_index}"
      break unless node.function.all_nodes(DabNodeDefineLocalVar).detect { |vdef| vdef.identifier == new_id }

      fun_index += 1
    end

    if xx
      errap ['all users:']
      node.all_users.each(&:dump)
    end

    node.all_users.each do |user|
      user.identifier = new_id
    end

    if xx
      err 'NOW:'
      node.function.dump
      err "\n\n\n#{('~' * 80).blue}"
    end
    true
  end
end
