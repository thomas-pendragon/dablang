require_relative 'node.rb'

class DabNodeSetter < DabNode
  def initialize(reference, value)
    super()
    insert(reference)
    insert(value)
  end

  def reference
    children[0]
  end

  def value
    children[1]
  end

  def lower!
    if reference.is_a? DabNodeReferenceIndex
      base = reference.base.compiled
      index = reference.index
      setcall = DabNodeInstanceCall.new(base, :[]=, [index, value])
      replace_with!(setcall)
      true
    end
    false
  end
end
