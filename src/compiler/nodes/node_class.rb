require_relative 'node.rb'

class DabNodeClass < DabNode
  attr_reader :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    identifier
  end

  def number
    root.class_number(@identifier)
  end

  def compile(output)
    output.comment(@identifier)
    output.print('PUSH_CLASS', number)
  end
end
