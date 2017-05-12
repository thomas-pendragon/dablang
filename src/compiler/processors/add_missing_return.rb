class AddMissingReturn
  def run(node)
    return if node.body.ends_with?(DabNodeReturn)
    node.body.insert(DabNodeReturn.new(DabNodeLiteralNil.new))
    true
  end
end
