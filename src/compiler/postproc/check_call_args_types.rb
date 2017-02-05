class DabPPCheckCallArgsTypes
  def run(program)
    program.visit_all(DabNodeCall) do |call|
      function = call.target_function
      next unless function.is_a? DabNodeFunction
      arglist = function.arglist
      call.args.each_with_index do |call_arg, index|
        arg = arglist[index]

        arg_type = arg.my_type
        value_type = call_arg.my_type

        next if arg_type.can_assign_from?(value_type)
        call_arg.add_error(DabCompileSetargTypeError.new(value_type, arg_type, call_arg))
      end
    end
  end
end
