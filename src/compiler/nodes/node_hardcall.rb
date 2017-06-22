require_relative 'node_basecall.rb'
require_relative '../../shared/opcodes.rb'

class DabNodeHardcall < DabNodeBasecall
  def initialize(identifier, args)
    super(args)
    pre_insert(identifier)
  end

  def identifier
    children[0]
  end

  def real_identifier
    identifier.extra_value
  end

  def args
    children[1..-1]
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    output.printex(self, 'HARDCALL', args.count.to_s)
  end

  def target_function
    root.has_function?(real_identifier)
  end
end
