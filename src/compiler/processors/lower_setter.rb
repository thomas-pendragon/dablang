class LowerSetter
  def run(node)
    reference = node.reference
    value = node.value
    if reference.is_a? DabNodeReferenceIndex
      base = reference.base.compiled
      index = reference.index
      setcall = DabNodeInstanceCall.new(base, :[]=, [index, value], nil)
      node.replace_with!(setcall)
      true
    elsif reference.is_a? DabNodeReferenceMember
      base = reference.base.compiled
      name = reference.name
      setcall = DabNodeInstanceCall.new(base, "#{name}=".to_sym, [value], nil)
      node.replace_with!(setcall)
      true
    elsif reference.is_a? DabNodeReferenceInstVar
      base = reference.compiled
      setcall = DabNodeSetInstVar.new(base.identifier, value)
      node.replace_with!(setcall)
      true
    elsif reference.is_a? DabNodeReferenceLocalVar
      setcall = DabNodeSetLocalVar.new(reference.name, value)
      node.replace_with!(setcall)
      true
    else
      raise "unknown reference #{reference}"
    end
  end
end
