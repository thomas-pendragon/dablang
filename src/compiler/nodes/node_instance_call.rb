require_relative 'node_basecall.rb'
require_relative '../processors/extract_call_block.rb'

class DabNodeInstanceCall < DabNodeBasecall
  lower_with ExtractCallBlock

  def initialize(value, identifier, arglist, block)
    super(arglist)
    pre_insert(identifier)
    pre_insert(block || DabNodeLiteralNil.new, 'block')
    pre_insert(value)
  end

  def value
    @children[0]
  end

  def block
    @children[1]
  end

  def has_block?
    !block.is_a?(DabNodeLiteralNil)
  end

  def identifier
    @children[2]
  end

  def args
    children[3..-1]
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
    end
    output.printex(self, has_block? ? 'INSTCALL_BLOCK' : 'INSTCALL', args.count)
  end

  def constant?
    value.constant?
  end

  def formatted_source(options)
    val = value.formatted_source(options)
    args = _formatted_arguments(options)
    if real_identifier == :[]
      "#{val}[#{args}]"
    else
      "#{val}.#{real_identifier}(#{args})"
    end
  end
end
