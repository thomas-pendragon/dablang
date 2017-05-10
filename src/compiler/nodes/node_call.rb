require_relative 'node_basecall.rb'
require_relative '../../shared/opcodes.rb'
require_relative '../processors/check_function_existence.rb'
require_relative '../processors/check_call_args_types.rb'
require_relative '../processors/check_call_args_count.rb'
require_relative '../processors/concreteify_call.rb'

class DabNodeCall < DabNodeBasecall
  check_with CheckFunctionExistence
  check_with CheckCallArgsTypes
  check_with CheckCallArgsCount
  optimize_with ConcreteifyCall

  def initialize(identifier, args)
    super()
    insert(identifier)
    args&.each { |arg| insert(arg) }
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
    if real_identifier == 'print'
      output.printex(self, 'KERNELCALL', KERNELCODES_REV['PRINT'])
    elsif real_identifier == 'exit'
      output.printex(self, 'KERNELCALL', KERNELCODES_REV['EXIT'])
    else
      output.push(identifier)
      output.comment(real_identifier)
      output.printex(self, 'CALL', args.count.to_s, '1')
    end
  end

  def target_function
    root.has_function?(real_identifier)
  end

  def formatted_source(options)
    argstxt = args.map { |item| item.formatted_source(options) }.join(', ')
    real_identifier + '(' + argstxt + ')' + ';'
  end
end
