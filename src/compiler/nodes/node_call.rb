require_relative 'node.rb'
require_relative '../../shared/opcodes.rb'

class DabNodeCall < DabNode
  def initialize(identifier, args)
    super()
    insert(identifier)
    args&.each { |arg| insert(arg) }
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

  def lower!
    if real_identifier == 'puts'
      pcall = DabNodeCall.new('print', args)
      args = DabNode.new
      args.insert(DabNodeLiteralString.new("\n"))
      endlcall = DabNodeCall.new('print', args)
      replace_with!([pcall, endlcall])
      return true
    end
    super
  end

  def preoptimize!
    if all_args_concrete?
      concreteify_call!
    else
      super
    end
  end

  def all_args_concrete?
    return false if target_function == true
    # TODO: WIP, run check first
    (args.count > 0) && (target_function.arglist.to_a.all? { |arg| arg.my_type.is_a? DabTypeAny }) && (target_function.argcount == args.count) && (args.all? { |arg| arg.my_type.concrete? })
  end

  def concreteify_call!
    return false if target_function == true
    fun = target_function.concreteify(args.map(&:my_type))
    call = DabNodeHardcall.new(fun, args.map(&:dup))
    replace_with!(call)
    true
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    if real_identifier == 'print'
      output.printex(self, 'KERNELCALL', KERNELCODES_REV['PRINT'])
    elsif real_identifier == 'exit'
      output.printex(self, 'KERNELCALL', KERNELCODES_REV['EXIT'])
    else
      output.push(identifier)
      output.comment(real_identifier)
      output.printex(self, 'CALL', args.count.to_s, '1')
    end
  end

  def target_function
    root.has_function?(real_identifier)
  end

  def formatted_source(options)
    argstxt = args.map { |item| item.formatted_source(options) }.join(', ')
    real_identifier + '(' + argstxt + ')' + ';'
  end
end
