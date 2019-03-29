class SSABreakPhiNodes
  def run(function)
    all_setters = function.all_nodes(DabNodeSSASet)
    return if all_setters.empty?

    all_setters.each(&:replace_with_register_set!)

    while true
      phi_nodes = function.all_nodes(DabNodeSSAPhi)
      break if phi_nodes.empty?

      phi_node = phi_nodes.last

      phi_setter = phi_node.parent

      replace_to = phi_setter.output_register

      phi_node.input_registers.each do |replace_from|
        function.all_nodes([DabNodeRegisterSet, DabNodeSSAGet]).each do |node|
          node.rename(replace_from, replace_to)
        end
      end

      phi_setter.remove!
    end

    function.all_nodes(DabNodeSSAGet).each do |node|
      register_get = DabNodeRegisterGet.new(node.input_register, node.input_varname)
      node.replace_with!(register_get)
    end
  end
end
