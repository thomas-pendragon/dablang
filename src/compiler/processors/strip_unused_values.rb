class StripUnusedValues
  def run(node)
    test = false
    node.each do |sub_node|
      if sub_node.no_side_effects?
        sub_node.remove!
        test = true
      end
    end
    test
  end
end
