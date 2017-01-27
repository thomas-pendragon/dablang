class DabPPCompactConstants
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      constant_counters = {}
      constant_remapping = {}
      function.visit_all(DabNodeConstantReference) do |constant_reference|
        constant_remapping[constant_reference.index] ||= constant_remapping.count
        constant_counters[constant_reference.index] ||= 0
        constant_counters[constant_reference.index] += 1
      end
      errap ['constant_counters', constant_counters, 'remapping', constant_remapping]

      to_remove = []
      function.visit_all(DabNodeConstant) do |constant|
        if constant_counters[constant.index].nil?
          to_remove << constant
        end
      end

      to_remove.each do |to_remove_node|
        function.remove_constant_node(to_remove_node)
      end

      function.visit_all([DabNodeConstant, DabNodeConstantReference]) do |node|
        node.index = constant_remapping[node.index]
      end
    end
  end
end
