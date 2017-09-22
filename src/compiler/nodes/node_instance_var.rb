require_relative 'node.rb'

class DabNodeInstanceVar < DabNode
  attr_accessor :identifier

  def initialize(identifier)
    super()
    insert(identifier[1..-1])
  end

  def node_identifier
    @children[0]
  end

  def identifier
    '@' + node_identifier.extra_value
  end

  def extra_dump
    identifier
  end

  def compile_as_ssa(output, output_register)
    output.comment(identifier)
    output.printex(self, 'Q_SET_INSTVAR', "R#{output_register}", "S#{node_identifier.index}")
  end

  def compile(output)
    output.push(node_identifier)
    output.print('PUSH_INSTVAR')
  end

  def formatted_source(_options)
    extra_dump
  end
end
