class StripExtraReturn
  def run(node)
    return unless node.multiple_returns?
    return unless node.function.flat?
    ret = false
    node.each do |child|
      if ret
        child.remove!
      elsif child.is_a?(DabNodeReturn)
        ret = true
      end
    end
    true
  end
end
