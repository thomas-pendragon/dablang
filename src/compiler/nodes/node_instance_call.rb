require_relative 'node.rb'
require_relative '../processors/extract_call_block.rb'

class DabNodeInstanceCall < DabNode
  lower_with ExtractCallBlock

  def initialize(value, identifier, arglist, block)
    super()
    insert(value)
    insert(block || DabNodeLiteralNil.new, 'block')
    insert(identifier)
    arglist.each { |arg| insert(arg) }
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
    output.printex(self, has_block? ? 'INSTCALL_BLOCK' : 'INSTCALL', args.count, 1)
  end

  def constant?
    value.constant?
  end

  def formatted_source(options)
    value.formatted_source(options) + ".#{real_identifier}(" + ')'
  end
end
