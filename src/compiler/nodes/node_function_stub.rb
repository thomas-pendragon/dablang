require_relative 'node.rb'

class DabNodeFunctionStub < DabNode
  attr_reader :identifier

  def initialize(identifier, _arglist = nil)
    super()
    @identifier = identifier
  end

  def concreteified?
    true
  end

  def compile_body(*args); end

  def compile_definition(*args); end

  def extra_dump
    identifier
  end

  def return_type
    DabType.parse(nil)
  end
end
