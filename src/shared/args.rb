args = ARGV.dup
flag = nil
$settings = {}

while args.count > 0
  arg = args.shift.strip
  next if arg.empty?
  if arg.start_with? '--'
    flag = arg[2..-1]
    value = true
    if flag['=']
      flag, value = flag.split('=', 2)
    end
    flag = flag.tr('-', '_').to_sym
    $settings[flag] = value
  else
    $settings[:input] = arg
    $settings[:inputs] ||= []
    $settings[:inputs] << arg
  end
end
