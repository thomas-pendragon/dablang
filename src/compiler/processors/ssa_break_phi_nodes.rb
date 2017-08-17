class SSABreakPhiNodes
  def run(function)
    phis = function.all_nodes(DabNodeSSAPhi)
    return if phis.count == 0
    phis.each do |phi|
      break_phi(function, phi)
    end
    true
  end

  def break_phi(function, phi)
    setter = phi.parent
    raise '?' unless setter.is_a?(DabNodeSSASet)

    reg_setters = function.all_nodes(DabNodeSSASet).select do |node|
      phi.input_registers.include?(node.output_register)
    end

    reg_setters.each do |reg_setter|
      reg_setter.rename(setter.output_register)
    end

    setter.remove!
  end
end
