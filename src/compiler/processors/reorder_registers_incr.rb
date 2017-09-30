class ReorderRegistersIncr
  def run(function)
    nodes = function.all_nodes(DabNodeRegisterSet)
    return if nodes.empty?
    registers = nodes.map(&:output_register)
    list = []
    registers.each do |reg|
      list << reg unless list.include?(reg)
    end
    mapping = {}
    list.each do |reg|
      mapping[reg] = mapping.count
    end
    return if mapping.all? { |key, value| key == value }
    nodes.each do |node|
      node.output_register = mapping[node.output_register]
    end
    function.all_nodes(DabNodeRegisterGet).each do |node|
      node.input_register = mapping[node.input_register]
    end
    true
  end
end
