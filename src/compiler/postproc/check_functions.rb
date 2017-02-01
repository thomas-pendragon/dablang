class DabPPCheckFunctions
  def run(program)
    program.visit_all(DabNodeCall) do |call|
      id = call.real_identifier
      unless program.has_function? id
        call.add_error(DabCompileUnknownFunctionError.new(id, call))
      end
    end
  end
end
