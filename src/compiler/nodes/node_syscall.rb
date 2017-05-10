require_relative 'node_basecall.rb'

class DabNodeSyscall < DabNodeBasecall
  def initialize(call, args)
    super()
    @call = call
    args&.each { |arg| insert(arg) }
  end

  def identifier
    KERNELCODES[@call]
  end

  def real_identifier
    identifier
  end

  def args
    children
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.printex(self, 'KERNELCALL', @call)
  end
end
