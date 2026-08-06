require_relative 'node'

class DabNodeFunctionStub < DabNode
  attr_reader :identifier, :ring_signature

  def initialize(identifier, _arglist = nil, is_static:, ring_signature: nil)
    super()
    @identifier = identifier
    @is_static = is_static
    @ring_signature = ring_signature
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
