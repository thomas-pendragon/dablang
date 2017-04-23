class DabPPConvertArgToLocalvar
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      next if function.arglist_converted
      function.arglist&.each_with_index do |arg, index|
        define_var = DabNodeDefineLocalVar.new(arg.identifier, DabNodeArg.new(index, arg.my_type), arg.my_type, true)
        define_var.clone_source_parts_from(arg)
        function.real_body.pre_insert(define_var)
      end
      function.arglist_converted = true
    end
  end
end
