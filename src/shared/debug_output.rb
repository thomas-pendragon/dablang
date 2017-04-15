require 'awesome_print'
require 'colorize'
require 'pry'
require 'pry-byebug'
require 'json'

def errn(str, *args)
  if args.count > 0
    str = sprintf(str, *args)
  end
  STDERR.print(str)
end

def err(str, *args)
  errn(str.to_s + "\n", *args)
end

def errap(arg)
  STDERR.puts arg.ai
end
