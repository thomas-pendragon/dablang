require_relative 'node_basecall.rb'
require_relative '../../shared/opcodes.rb'
require_relative '../processors/extract_call_block.rb'

class DabNodeHardcall < DabNodeBasecall
  lower_with ExtractCallBlock

  def initialize(identifier, args, block)
    super(args)
    pre_insert(block || DabNodeLiteralNil.new, 'block')
    pre_insert(identifier)
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
    output.printex(self, has_block? ? 'HARDCALL_BLOCK' : 'HARDCALL', args.count.to_s)
  end

  def target_function
    root.has_function?(real_identifier)
  end
end
