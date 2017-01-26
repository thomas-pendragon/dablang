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

  def args
    children[1..-1]
  end

  def compile(output)
    output.push(identifier)
    args.each { |arg| arg.compile(output) }
    output.comment(identifier.extra_value)
    output.print('CALL', args.count.to_s)
  end
end
