require_relative 'node_external_basecall.rb'
require_relative '../../shared/opcodes.rb'

class DabNodeHardcall < DabNodeExternalBasecall
  def initialize(identifier, args, block, block_capture)
    super(args)
    pre_insert(block_capture || DabNodeLiteralNil.new)
    pre_insert(block || DabNodeLiteralNil.new)
    pre_insert(identifier)
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

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    if has_block?
      output.push(block.identifier)
      block_capture.compile(output)
    end
    output.printex(self, has_block? ? 'HARDCALL_BLOCK' : 'HARDCALL', args.count.to_s)
  end
end
