class DabPPCheckCallArgsCount
  def run(program)
    program.visit_all(DabNodeCall) do |call|
      function = call.target_function
      next unless function.is_a? DabNodeFunction
      arglist = function.arglist
      actual = call.args.count
      expected = arglist.count
      if actual != expected
        func = function.identifier
        call.add_error(DabCompileCallArgCountError.new(func, actual, expected, call))
      end
    end
  end
end
