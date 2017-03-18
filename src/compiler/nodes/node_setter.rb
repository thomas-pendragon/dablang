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
    elsif reference.is_a? DabNodeReferenceMember
      base = reference.base.compiled
      name = reference.name
      setcall = DabNodeInstanceCall.new(base, "#{name}=".to_sym, [value])
      replace_with!(setcall)
      true
    else
      raise "unknown reference #{reference}"
    end
    false
  end

  def formatted_source(options)
    reference.formatted_source(options) + ' = ' + value.formatted_source(options) + ';'
  end
end
