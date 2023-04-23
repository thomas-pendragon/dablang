require_relative 'node_external_basecall'
require_relative '../processors/simplify_class_property'
require_relative '../processors/check_instance_function_existence'
require_relative '../processors/uncomplexify'

class DabNodeInstanceCall < DabNodeExternalBasecall
  optimize_with SimplifyClassProperty
  check_with CheckInstanceFunctionExistence
  lower_with Uncomplexify
  early_after_init BlockToVariable

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

  def block_symbol_index
    block.identifier.index
  end

  def args
    self[4..-1]
  end

  def real_identifier
    identifier.extra_value
  end

  def all_real_args
    self_register = value.input_register
    [self_register] + args.map(&:input_register)
  end

  def protect_register(output,reg)
    @retains = []
    i = 0
    all_real_args.each do |areg|
      if reg == areg
          new_reg = function.allocate_new_tmp_reg + i
          i += 1          
          output.print('MOV', "R#{new_reg}", "R#{reg}")
          output.print('RETAIN', "R#{new_reg}")
          @retains << new_reg
        if reg == value.input_register # self
          value.input_register = new_reg
        else 
          args.each do |arg|
            if arg.input_register == reg
              arg.input_register = new_reg
            end
          end
        end
      end
    end
  end

  def _compile(output, output_register)
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

    output.printex(self, 'INSTCALL', *args)

    @retains.each do |reg|
      output.print("RELEASE", "R#{reg}")
    end
  end

  def compile_as_ssa(output, output_register)
    _compile(output, output_register)
  end

  def compile_top_level(output)
    @retains = []
    _compile(output, nil)
  end

  def symbol_index
    identifier.symbol_index
  end

  def formatted_source(options)
    val = value.formatted_source(options)
    args = _formatted_arguments(options)
    ret = if real_identifier == '[]'
            "#{val}[#{args}]"
          else
            "#{val}.#{real_identifier}(#{args})"
          end
    ret + formatted_block(options)
  end

  def uncomplexify_args
    list = args + [value]
    list += [block_capture] if has_block?
    list
  end

  def accepts?(arg)
    arg.register?
  end
end
