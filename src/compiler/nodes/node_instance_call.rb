require_relative 'node_external_basecall.rb'
require_relative '../processors/simplify_class_property.rb'
require_relative '../processors/check_instance_function_existence.rb'
require_relative '../processors/uncomplexify.rb'

class DabNodeInstanceCall < DabNodeExternalBasecall
  optimize_with SimplifyClassProperty
  check_with CheckInstanceFunctionExistence
  lower_with Uncomplexify

  def initialize(value, identifier, arglist, block)
    super(arglist)
    pre_insert(DabNodeLiteralNil.new)
    pre_insert(identifier)
    pre_insert(block || DabNodeLiteralNil.new)
    pre_insert(value)
  end

  def children_info
    {
      identifier => 'identifier',
      block => 'block',
      value => 'value',
      block_capture => 'block_capture',
    }
  end

  def value
    self[0]
  end

  def block
    self[1]
  end

  def has_block?
    !block.is_a?(DabNodeLiteralNil)
  end

  def identifier
    self[2]
  end

  def block_capture
    self[3]
  end

  def args
    self[4..-1]
  end

  def real_identifier
    identifier.extra_value
  end

  def _compile(output, output_register)
    if has_block? || !identifier.is_a?(DabNodeConstantReference)
      compile(output)
      if output_register
        output.print('Q_SET_POP', "R#{output_register}")
      else
        output.print('POP', 1)
      end
      return
    end

    output.comment(self.real_identifier)
    list = args.map(&:input_register).map { |arg| "R#{arg}" }
    self_register = value.input_register
    list = nil if list.empty?
    args = [
      output_register.nil? ? 'RNIL' : "R#{output_register}",
      "R#{self_register}",
      "S#{symbol_index}",
      list,
    ]
    output.printex(self, 'Q_SET_INSTCALL', *args)
  end

  def compile_as_ssa(output, output_register)
    _compile(output, output_register)
  end

  def compile_top_level(output)
    _compile(output, nil)
  end

  def symbol_index
    identifier.index
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    value.compile(output)
    output.push(identifier)
    if has_block?
      output.push(block.identifier)
      block_capture.compile(output)
    end
    output.printex(self, has_block? ? 'INSTCALL_BLOCK' : 'INSTCALL', args.count)
  end

  def formatted_source(options)
    val = value.formatted_source(options)
    args = _formatted_arguments(options)
    ret = if real_identifier == :[]
            "#{val}[#{args}]"
          else
            "#{val}.#{real_identifier}(#{args})"
          end
    ret + formatted_block(options)
  end

  def uncomplexify_args
    args + [value]
  end

  def accepts?(arg)
    arg.register?
  end
end
