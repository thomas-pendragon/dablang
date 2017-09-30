class ReorderRegisters
  def run(function)
    nodes = function.all_nodes(DabNodeRegisterSet)
    return if nodes.empty?
    registers = nodes.map(&:output_register)
    unique_registers = registers.uniq
    return if (unique_registers.count - 1) == unique_registers.max
    mapping = {}
    unique_registers.each do |reg|
      mapping[reg] = mapping.count
    end
    nodes.each do |node|
      node.output_register = mapping[node.output_register]
    end
    function.all_nodes(DabNodeRegisterGet).each do |node|
      node.input_register = mapping[node.input_register]
    end
    true
  end
end
