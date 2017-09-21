require_relative 'node_external_basecall.rb'
require_relative '../../shared/opcodes.rb'
require_relative '../processors/check_call_args_count.rb'
require_relative '../processors/check_call_args_types.rb'
require_relative '../processors/check_function_existence.rb'
require_relative '../processors/concreteify_call.rb'
require_relative '../processors/convert_call_to_syscall.rb'
require_relative '../processors/uncomplexify.rb'

class DabNodeCall < DabNodeExternalBasecall
  dirty_check_with CheckFunctionExistence
  dirty_check_with CheckCallArgsTypes
  dirty_check_with CheckCallArgsCount
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

  def compile_as_ssa(output, output_register)
    unless identifier.is_a? DabNodeConstantReference
      raise 'symbol must be reference' unless $no_constants
      compile(output)
      output.print('Q_SET_POP', "R#{output_register}")
      return
    end

    output.comment(self.real_identifier)
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    list = nil if list.empty?

    blockarg = "S#{block_symbol_index}" if has_block?
    capture_arg = "R#{block_capture.input_register}" if has_block?
    args = [
      "R#{output_register}",
      "S#{symbol_index}",
      blockarg,
      capture_arg,
      list,
    ].compact

    output.printex(self, 'Q_SET_CALL' + (has_block? ? '_BLOCK' : ''), *args)
  end

  def compile_top_level(output)
    unless identifier.is_a? DabNodeConstantReference
      raise 'symbol must be reference' unless $no_constants
      compile(output)
      output.print('POP', 1)
      return
    end

    blockarg = "S#{block_symbol_index}" if has_block?
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    if has_block?
      capture_arg = "R#{block_capture.input_register}"
    end
    args = ["S#{symbol_index}", blockarg, capture_arg, list].compact
    output.comment(self.real_identifier)
    output.printex(self, 'Q_VOID_CALL' + (has_block? ? '_BLOCK' : ''), *args)
  end

  def symbol_index
    identifier.index
  end

  def block_symbol_index
    block.identifier.index
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    if has_block?
      output.push(block.identifier)
      block_capture.compile(output)
    end
    output.printex(self, has_block? ? 'CALL_BLOCK' : 'CALL', args.count.to_s)
  end

  def formatted_source(options)
    real_identifier + '(' + _formatted_arguments(options) + ')' + formatted_block(options)
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
    target_function.concreteified? ? '[hardcall]' : ''
  end
end
