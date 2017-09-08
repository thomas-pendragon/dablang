require_relative 'node_basecall.rb'
require_relative '../../shared/opcodes.rb'
require_relative '../processors/extract_call_block.rb'

class DabNodeHardcall < DabNodeBasecall
  lower_with ExtractCallBlock

  def initialize(identifier, args, block)
    super(args)
    pre_insert(block || DabNodeLiteralNil.new)
    pre_insert(identifier)
  end

  def children_info
    {
      identifier => 'identifier',
      block => 'block',
    }
  end

  def identifier
    self[0]
  end

  def block
    self[1]
  end

  def real_identifier
    identifier.extra_value
  end

  def args
    self[2..-1]
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    if has_block?
      output.push(block.identifier)
    end
    output.printex(self, has_block? ? 'HARDCALL_BLOCK' : 'HARDCALL', args.count.to_s)
  end
end
