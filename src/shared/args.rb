args = ARGV.dup
flag = nil
$settings = {}

while args.count > 0
  arg = args.shift.strip
  next if arg.empty?
  flag = nil if arg.start_with? '--'
  if flag.nil?
    if arg.start_with? '--'
      flag = arg[2..-1].tr('-', '_').to_sym
      $settings[flag] = true
    else
      $settings[:input] = arg
      $settings[:inputs] ||= []
      $settings[:inputs] << arg
    end
  else
    $settings[flag] = arg
    flag = nil
  end
end
