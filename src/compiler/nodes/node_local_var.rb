require_relative 'node.rb'

class DabNodeLocalVar < DabNode
  attr_accessor :index
  attr_accessor :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    @identifier
  end

  def real_identifier
    identifier
  end

  def compile(output)
    raise 'no index' unless @index
    output.comment("var #{index} #{identifier}")
    output.print('PUSH_VAR', index)
  end
end
