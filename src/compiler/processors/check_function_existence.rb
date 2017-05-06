class CheckFunctionExistence
  def run(call)
    id = call.real_identifier
    unless call.root.has_function? id
      call.add_error(DabCompileUnknownFunctionError.new(id, call))
      true
    end
  end
end
