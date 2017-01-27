class DabPPReuseConstants
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      constant_indices = {}
      function.visit_all(DabNodeConstant) do |constant|
        constant_indices[constant.extra_value] ||= constant.index
      end
      errap ['indices', constant_indices]
      function.visit_all(DabNodeConstantReference) do |constant_reference|
        constant_reference.index = constant_indices[constant_reference.extra_value]
      end
    end
  end
end
