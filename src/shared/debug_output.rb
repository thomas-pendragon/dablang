def errn(str, *args)
  if args.count > 0
    str = sprintf(str, *args)
  end
  STDERR.print(str)
end

def err(str, *args)
  errn("#{str}\n", *args)
end

def errap(arg)
  warn arg.ai
end
