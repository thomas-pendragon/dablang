class CheckCallArgsCount
  def run(call)
    function = call.target_function
    return false unless function.is_a? DabNodeFunction

    actual = call.args.count
    expected_min = function.min_argc
    expected_max = function.max_argc
    expected = if expected_min == expected_max
                 expected_min
               else
                 expected_min..expected_max
               end
    if actual < expected_min || actual > expected_max
      func = function.identifier
      call.add_error(DabCompileCallArgCountError.new(func, actual, expected, call))
      return true
    end
    false
  end
end
