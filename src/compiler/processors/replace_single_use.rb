class ReplaceSingleUse
  def run(node)
    var_defs = node.all_nodes(DabNodeDefineLocalVar)
    var_defs.each do |var|
      next unless var.all_setters.count == 1
      value = var.value
      next unless value.no_side_effects?
      getters = var.all_getters
      getters.each do |getter|
        getter.replace_with!(value.dup)
      end
      var.remove!
      return true
    end

    false
  end
end
