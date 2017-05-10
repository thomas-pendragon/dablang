class SimplifyConstantProperty
  def run(node)
    if node.constant?
      simplified = node.simplify_constant
      if simplified
        node.replace_with!(simplified)
        return true
      end
    end
    false
  end
end
