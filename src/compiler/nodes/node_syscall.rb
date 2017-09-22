require_relative 'node_basecall.rb'
require_relative '../processors/uncomplexify.rb'

class DabNodeSyscall < DabNodeBasecall
  lower_with Uncomplexify

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
    output.comment(self.extra_value)
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    output.printex(self, 'Q_SET_SYSCALL', "R#{output_register}", @call, list)
  end

  def compile_top_level(output)
    output.comment(self.extra_value)
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    output.printex(self, 'Q_SET_SYSCALL', 'RNIL', @call, list)
  end

  def target_function
    nil
  end

  def uncomplexify_args
    args
  end

  def accepts?(arg)
    arg.register?
  end
end
