require_relative 'node_basecall.rb'
require_relative '../../shared/opcodes.rb'
require_relative '../processors/check_call_args_count.rb'
require_relative '../processors/check_call_args_types.rb'
require_relative '../processors/check_function_existence.rb'
require_relative '../processors/concreteify_call.rb'
require_relative '../processors/convert_call_to_syscall.rb'

class DabNodeCall < DabNodeBasecall
  check_with CheckFunctionExistence
  check_with CheckCallArgsTypes
  check_with CheckCallArgsCount
  lower_with ConvertCallToSyscall
  optimize_with ConcreteifyCall

  def initialize(identifier, args)
    super(args)
    pre_insert(identifier)
  end

  def identifier
    children[0]
  end

  def real_identifier
    identifier.extra_value
  end

  def args
    children[1..-1]
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    output.printex(self, 'CALL', args.count.to_s, '1')
  end

  def target_function
    root.has_function?(real_identifier)
  end

  def _formatted_arguments(options)
    args.map { |item| item.formatted_source(options) }.join(', ')
  end

  def formatted_source(options)
    real_identifier + '(' + _formatted_arguments(options) + ')' + ';'
  end
end
