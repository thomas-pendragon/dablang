class StripUnusedValues
  def run(node)
    test = false
    node.each do |sub_node|
      if sub_node.is_a?(DabNodeLiteral) || sub_node.is_a?(DabNodeConstantReference)
        sub_node.remove!
        test = true
      end
    end
    test
  end
end
