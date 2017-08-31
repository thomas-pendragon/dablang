require_relative 'node_basecall.rb'

class DabNodeSyscall < DabNodeBasecall
  def initialize(call, args)
    super(args)
    @call = call
  end

  def extra_dump
    sprintf('#%x %s', @call, identifier)
  end

  def identifier
    KERNELCODES[@call]
  end

  def real_identifier
    identifier
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.printex(self, 'SYSCALL', @call)
  end

  def compile_as_ssa(output, output_register)
    args.each { |arg| arg.compile(output) }
    output.comment(self.extra_value)
    output.printex(self, 'Q_SET_SYSCALL_STACK', "R#{output_register}", @call)
  end

  def target_function
    nil
  end
end
