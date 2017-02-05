class DabPPCheckSetvarTypes
  def run(program)
    program.visit_all(DabNodeDefineLocalVar) do |setvar|
      var_type = setvar.my_type
      value_type = setvar.value.my_type
      unless var_type.can_assign_from?(value_type)
        setvar.add_error(DabCompileSetvarTypeError.new(value_type, var_type, setvar))
      end
    end
  end
end
