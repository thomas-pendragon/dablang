require_relative 'node_basecall.rb'
require_relative '../../shared/opcodes.rb'
require_relative '../processors/check_call_args_count.rb'
require_relative '../processors/check_call_args_types.rb'
require_relative '../processors/check_function_existence.rb'
require_relative '../processors/concreteify_call.rb'
require_relative '../processors/convert_call_to_syscall.rb'
require_relative '../processors/extract_call_block.rb'

class DabNodeCall < DabNodeBasecall
  check_with CheckFunctionExistence
  check_with CheckCallArgsTypes
  check_with CheckCallArgsCount
  lower_with ConvertCallToSyscall
  optimize_with ConcreteifyCall
  lower_with ExtractCallBlock

  def initialize(identifier, args, block)
    super(args)
    pre_insert(block || DabNodeLiteralNil.new, 'block')
    pre_insert(DabNodeSymbol.new(identifier), 'identifier')
  end

  def identifier
    children[0]
  end

  def block
    children[1]
  end

  def real_identifier
    identifier.extra_value
  end

  def args
    children[2..-1]
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    if has_block?
      output.push(block.identifier)
    end
    output.printex(self, has_block? ? 'CALL_BLOCK' : 'CALL', args.count.to_s)
  end

  def target_function
    root.has_function?(real_identifier)
  end

  def formatted_source(options)
    real_identifier + '(' + _formatted_arguments(options) + ')' + formatted_block(options)
  end
end
