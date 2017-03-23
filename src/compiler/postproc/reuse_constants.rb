class DabPPReuseConstants
  def run(program)
    constant_indices = {}
    program.visit_all(DabNodeConstant) do |constant|
      constant_indices[constant.extra_value] ||= constant.index
    end
    program.visit_all(DabNodeFunction) do |function|
      errap ['indices', constant_indices] if $debug
      function.visit_all(DabNodeConstantReference) do |constant_reference|
        constant_reference.index = constant_indices[constant_reference.extra_value]
      end
    end
  end
end
