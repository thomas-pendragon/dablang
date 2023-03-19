class ConvertArgToLocalvar
  def run(function)
    list = function.arglist&.to_a || []
    list.reverse_each do |arg|
      index = list.index(arg)
      default_value = arg.default_value&.dup
      if default_value
        defid = "#{arg.identifier}_def"
        define_var_def = DabNodeDefineLocalVar.new(defid, default_value)
        getter = DabNodeLocalVar.new(defid)
      end
      define_var = DabNodeDefineLocalVar.new(arg.identifier, DabNodeArg.new(index, getter), arg.my_type)
      define_var.clone_source_parts_from(arg)
      function.blocks[0].pre_insert(define_var)
      function.blocks[0].pre_insert(define_var_def) if define_var_def
    end
  end
end
