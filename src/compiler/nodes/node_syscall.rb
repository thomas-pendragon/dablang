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

  def _compile(output, output_register)
    output.comment(identifier)
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    output.printex(self, 'Q_SET_SYSCALL', output_register, @call, list)
  end

  def compile_as_ssa(output, output_register)
    _compile(output, "R#{output_register}")
  end

  def compile_top_level(output)
    _compile(output, 'RNIL')
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

  def formatted_source(options)
    "sys_#{real_identifier}(" + _formatted_arguments(options) + ')' + formatted_block(options)
  end
end
