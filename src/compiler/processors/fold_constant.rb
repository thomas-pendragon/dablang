class FoldConstant
  def run(node)
    left = node.left
    right = node.right
    identifier = node.identifier
    return unless left.constant? && right.constant?
    id = identifier.extra_value
    lv = left.constant_value
    rv = right.constant_value
    numeric = (lv.is_a? Numeric) && (rv.is_a? Numeric)
    return if id == 'is'
    if id == '||'
      node.replace_with!((lv.nil? || lv == 0 || lv == '' || lv == false) ? right : left)
      return true
    end
    if id == '&&'
      node.replace_with!((lv.nil? || lv == 0 || lv == '' || lv == false) ? left : right)
      return true
    end
    if numeric && %w(+ - * / % |).include?(id)
      node.replace_with! DabNodeLiteralNumber.new(lv.send(id, rv))
      return true
    elsif numeric && %w(> >= < <=).include?(id)
      node.replace_with! DabNodeLiteralBoolean.new(lv.send(id, rv))
      return true
    elsif %w(== !=).include?(id)
      if (lv.is_a? DabType) && (rv.is_a? DabType)
        lv = lv.class
        rv = rv.class
      end
      node.replace_with! DabNodeLiteralBoolean.new(lv.send(id, rv))
      return true
    else
      raise "don't know how to fold #{lv.class} #{id} #{rv.class}"
    end
  end
end
