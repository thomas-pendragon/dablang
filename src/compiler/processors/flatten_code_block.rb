class FlattenCodeBlock
  def run(node)
    node.children.each_with_index do |child, _index|
      next unless child.is_a? DabNodeCodeBlockEx
      node.splice(child) do |cont|
        child.insert(DabNodeJump.new(cont))
        [child]
      end
      return true
    end
    false
  end
end
