require_relative 'node.rb'

class DabNodeMethodReference < DabNode
  attr_reader :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def compile(output)
    output.print('PUSH_METHOD', @identifier)
  end
end
