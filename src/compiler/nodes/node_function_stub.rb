require_relative 'node'

class DabNodeFunctionStub < DabNode
  attr_reader :identifier

  def initialize(identifier, _arglist = nil, is_static:)
    super()
    @identifier = identifier
    @is_static = is_static
  end

  def concreteified?
    true
  end

  def is_static?
    @is_static
  end

  def compile_body(*args); end

  def compile_definition(*args); end

  def extra_dump
    identifier
  end

  def return_type
    DabType.parse(nil)
  end

  def create_attribute_init(body); end
end
