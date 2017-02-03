require_relative 'node.rb'

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

  def compile(output)
    args.each { |arg| arg.compile(output) }
    output.push(identifier)
    output.comment(real_identifier)
    output.print('CALL', args.count.to_s)
  end
end
