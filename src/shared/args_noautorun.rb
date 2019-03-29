def read_args!(input = nil)
  args = input || ARGV.dup
  flag = nil
  settings = {}
  $autofix = ENV['AUTOFIX'] == '1'

  while args.count > 0
    arg = args.shift.strip
    next if arg.empty?

    if arg.start_with? '--'
      flag = arg[2..-1]
      value = true
      if flag['=']
        flag, value = flag.split('=', 2)
      end
      flag = flag.tr('-', '_')
      if flag['[]']
        flag['[]'] = ''
        flag = flag.to_sym
        settings[flag] ||= []
        settings[flag] << value
      else
        flag = flag.to_sym
        settings[flag] = value
      end
    else
      settings[:input] = arg
      settings[:inputs] ||= []
      settings[:inputs] << arg
    end
  end

  $settings = settings
  settings
end
