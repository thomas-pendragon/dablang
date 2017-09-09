require_relative 'node_basecall.rb'
require_relative '../processors/extract_call_block.rb'
require_relative '../processors/simplify_class_property.rb'
require_relative '../processors/check_instance_function_existence.rb'

class DabNodeInstanceCall < DabNodeBasecall
  lower_with ExtractCallBlock
  optimize_with SimplifyClassProperty
  check_with CheckInstanceFunctionExistence

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
end
