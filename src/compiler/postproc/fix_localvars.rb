class DabPPFixLocalvars
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      local_vars = {}
      function.visit_all(DabNodeDefineLocalVar) do |node|
        node.index = local_vars.count
        local_vars[node.real_identifier] = node.index
      end
      function.visit_all(DabNodeSetLocalVar) do |node|
        node.index = local_vars[node.real_identifier]
      end
      function.visit_all(DabNodeLocalVar) do |node|
        node.index = local_vars[node.real_identifier]
      end
    end
  end
end
