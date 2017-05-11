class ConvertArgToLocalvar
  def run(function)
    function.arglist&.each_with_index do |arg, index|
      define_var = DabNodeDefineLocalVar.new(arg.identifier, DabNodeArg.new(index), arg.my_type, true)
      define_var.clone_source_parts_from(arg)
      function.body.pre_insert(define_var)
    end
  end
end
