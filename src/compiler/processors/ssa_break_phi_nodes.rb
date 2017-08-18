class SSABreakPhiNodes
  def run(function)
    all_setters = function.all_nodes(DabNodeSSASet)
    return if all_setters.empty?

    variables = {}

    all_setters.each do |setter|
      variables[setter.output_varname] ||= []
      variables[setter.output_varname] << setter
    end

    variables.each do |variable, setters|
      break_regs(function, variable, setters)
    end

    function.all_nodes(DabNodeSSAPhi).each do |node|
      node.parent.remove!
    end
  end

  def break_regs(_function, variable, setters)
    first_reg = setters.first.output_register
    setters.each do |setter|
      setter.rename(first_reg)
      value = setter.value.extract
      new_setter = DabNodeRegisterSet.new(value, first_reg, variable)
      setter.replace_with!(new_setter)
    end
  end
end
