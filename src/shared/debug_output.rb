require_relative 'test_output'

def errn(str, *args)
  if args.count > 0
    str = sprintf(str, *args)
  end
  DabTestOutput.emit(str)
end

def err(str, *args)
  errn("#{str}\n", *args)
end

def errap(arg)
  warn arg.ai
end
