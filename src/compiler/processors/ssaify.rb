class SSAify
  def run(node)
    vars = node.variables
    return if vars.empty?
    vars.each do |var|
      ssaify_variable(node, var)
    end
    true
  end

  def ssaify_variable(function, variable)
    setters = variable.all_setters
    getters = variable.all_getters

    last_setters = {}
    getters.each do |getter|
      last_setters[getter] = getter.last_var_setter
    end

    setters.each do |setter|
      reg = function.allocate_ssa
      value = setter.value.extract
      identifier = setter.identifier
      new_setter = DabNodeSSASet.new(value, reg, identifier)
      last_setters.each do |getter, last_setter|
        new_getter = DabNodeSSAGet.new(reg, identifier)
        getter.replace_with!(new_getter) if last_setter == setter
      end
      setter.replace_with!(new_setter)
    end
  end
end
