require_relative 'node.rb'

class DabNodePropertyGet < DabNode
  def initialize(value, identifier)
    super()
    insert(value)
    insert(identifier)
  end

  def value
    @children[0]
  end

  def identifier
    @children[1]
  end

  def real_identifier
    identifier.extra_value
  end

  def compile(output)
    value.compile(output)
    output.push(identifier)
    output.comment(".#{real_identifier}")
    output.print('PROPGET')
  end
end
