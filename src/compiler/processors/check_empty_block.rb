class CheckEmptyBlock
  def run(node)
    return if node.embedded?

    if node.empty?
      node.function.dump
      err '--~' * 50
      node.dump
      raise 'internal compiler error: empty block'
    end
    false
  end
end
