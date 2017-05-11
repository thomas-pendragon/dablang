class FoldConstant
  def run(node)
    left = node.left
    right = node.right
    identifier = node.identifier
    return false unless left.constant? && right.constant?
    id = identifier.extra_value
    lv = left.constant_value
    rv = right.constant_value
    numeric = (lv.is_a? Numeric) && (rv.is_a? Numeric)
    if id == 'is'
      raise "is: rhs must be class, got #{rv.class}" unless rv.is_a? DabType
      value = rv.belongs?(lv)
      node.replace_with!(DabNodeLiteralBoolean.new(value))
      return true
    end
    if id == '||'
      node.replace_with!((lv.nil? || lv == 0 || lv == '' || lv == false) ? right : left)
      return true
    end
    if id == '&&'
      node.replace_with!((lv.nil? || lv == 0 || lv == '' || lv == false) ? left : right)
      return true
    end
    if numeric && %w(+ - * / %).include?(id)
      node.replace_with! DabNodeLiteralNumber.new(lv.send(id, rv))
      return true
    elsif %w(== !=).include?(id)
      node.replace_with! DabNodeLiteralBoolean.new(lv.send(id, rv))
      return true
    else
      raise "don't know how to fold #{lv.class} #{id} #{rv.class}"
    end
  end
end
