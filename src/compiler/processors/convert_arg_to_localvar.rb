class ConvertArgToLocalvar
  def run(function)
    list = function.arglist&.to_a || []
    list.reverse.each do |arg|
      index = list.index(arg)
      define_var = DabNodeDefineLocalVar.new(arg.identifier, DabNodeArg.new(index), arg.my_type)
      define_var.clone_source_parts_from(arg)
      function.blocks[0].pre_insert(define_var)
    end
  end
end
