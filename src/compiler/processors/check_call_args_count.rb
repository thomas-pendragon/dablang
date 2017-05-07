class CheckCallArgsCount
  def run(call)
    function = call.target_function
    return false unless function.is_a? DabNodeFunction
    arglist = function.arglist
    actual = call.args.count
    expected = arglist.count
    if actual != expected
      func = function.identifier
      call.add_error(DabCompileCallArgCountError.new(func, actual, expected, call))
      return true
    end
    false
  end
end
