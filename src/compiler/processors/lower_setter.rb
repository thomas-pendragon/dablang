class LowerSetter
  def run(node)
    reference = node.reference
    value = node.value
    case reference
    when DabNodeReferenceIndex
      base = reference.base.compiled
      index = reference.index
      setcall = DabNodeInstanceCall.new(base, :[]=, [index, value], nil)
      node.replace_with!(setcall)
      true
    when DabNodeReferenceMember
      base = reference.base.compiled
      name = reference.name
      setcall = DabNodeInstanceCall.new(base, :"#{name}=", [value], nil)
      node.replace_with!(setcall)
      true
    when DabNodeReferenceInstVar
      base = reference.compiled
      setcall = DabNodeSetInstVar.new(base.identifier, value)
      node.replace_with!(setcall)
      true
    when DabNodeReferenceClassVar
      base = reference.compiled
      setcall = DabNodeSetClassVar.new(base.identifier, value)
      node.replace_with!(setcall)
      true
    when DabNodeReferenceLocalVar
      setcall = DabNodeSetLocalVar.new(reference.name, value)
      node.replace_with!(setcall)
      true
    else
      raise "unknown reference #{reference}"
    end
  end
end
