class ExtractLiteral
  def run(literal)
    return if $no_constants
    return if literal.is_a? DabNodeLiteralNil

    parent = literal.parent
    if literal.parent.is_a? DabNodeConstant
      false
    else
      replacement = literal.root.add_constant(literal)
      parent.replace_child(literal, replacement)
      true
    end
  end
end
