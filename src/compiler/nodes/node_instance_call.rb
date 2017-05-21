require_relative 'node.rb'

class DabNodeInstanceCall < DabNode
  def initialize(value, identifier, arglist)
    super()
    insert(value)
    insert(identifier)
    arglist.each { |arg| insert(arg) }
  end

  def value
    @children[0]
  end

  def identifier
    @children[1]
  end

  def args
    children[2..-1]
  end

  def real_identifier
    identifier.extra_value
  end

  def compile(output)
    args.each { |arg| arg.compile(output) }
    value.compile(output)
    output.push(identifier)
    output.printex(self, 'INSTCALL', args.count, 1)
  end

  def constant?
    value.constant?
  end

  def formatted_source(options)
    value.formatted_source(options) + ".#{real_identifier}(" + ')'
  end
end
