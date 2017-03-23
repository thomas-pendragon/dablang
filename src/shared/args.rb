args = ARGV.dup
flag = nil
$settings = {}

while args.count > 0
  arg = args.shift
  if flag.nil?
    if arg.start_with? '--'
      flag = arg[2..-1].to_sym
      $settings[flag] = true
    else
      $settings[:input] = arg
    end
  else
    $settings[flag] = arg
    flag = nil
  end
end
