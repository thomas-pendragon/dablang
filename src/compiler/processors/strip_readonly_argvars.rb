class StripReadonlyArgvars
  def run(node)
    return false if node.all_setters.count > 1
    value = node.value
    return false unless value.is_a? DabNodeArg
    node.all_getters.each do |get_node|
      get_node.replace_with!(value.dup)
    end
    node.remove!
    true
  end
end
