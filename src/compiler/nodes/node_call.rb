require_relative 'node_external_basecall'
require_relative '../../shared/opcodes'
require_relative '../processors/check_call_args_count'
require_relative '../processors/check_call_args_types'
require_relative '../processors/check_function_existence'
require_relative '../processors/concreteify_call'
require_relative '../processors/convert_call_to_syscall'
require_relative '../processors/uncomplexify'
require_relative '../processors/block_to_variable'

class DabNodeCall < DabNodeExternalBasecall
  dirty_check_with CheckFunctionExistence
  dirty_check_with CheckCallArgsTypes
  dirty_check_with CheckCallArgsCount
  early_after_init BlockToVariable
  lower_with ConvertCallToSyscall
  lower_with Uncomplexify
  optimize_with ConcreteifyCall

  def initialize(identifier, args, block, block_capture = nil)
    super(args)
    pre_insert(block_capture || DabNodeLiteralNil.new)
    pre_insert(block || DabNodeLiteralNil.new)
    pre_insert(DabNodeSymbol.new(identifier))
  end

  def children_info
    {
      identifier => 'identifier',
      block => 'block',
      block_capture => 'block_capture',
    }
  end

  def identifier
    self[0]
  end

  def block
    self[1]
  end

  def block_capture
    self[2]
  end

  def real_identifier
    identifier.extra_value
  end

  def args
    self[3..-1]
  end

  def _compile(output, output_register)
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    list = nil if list.empty?

    args = [
      output_register.nil? ? 'RNIL' : "R#{output_register}",
      "S#{symbol_index}",
      list,
    ]

    output.comment(self.real_identifier)
    output.printex(self, 'CALL', *args)
  end

  def compile_as_ssa(output, output_register)
    _compile(output, output_register)
  end

  def compile_top_level(output)
    _compile(output, nil)
  end

  def symbol_index
    identifier.symbol_index
  end

  def block_symbol_index
    block.identifier.symbol_index
  end

  def formatted_source(options)
    "#{real_identifier}(#{_formatted_arguments(options)})#{formatted_block(options)}"
  end

  def my_type
    return DabTypeObject.new if target_function == true || target_function == false

    target_function&.return_type
  end

  def uncomplexify_args
    list = args
    list += [block_capture] if has_block?
    list
  end

  def accepts?(arg)
    arg.register?
  end

  def extra_dump
    return '[??]' if target_function.nil?
    return '[builtin]' if target_function == true
    return '[builtin??]' if target_function == false

    target_function.concreteified? ? '[hardcall]' : ''
  end

  def arg_count
    args.select { _1.count_as_argument? }.count
  end
end
