require_relative 'node.rb'
require_relative '../concerns/localvar_definition_concern.rb'

class DabNodeLocalVar < DabNode
  include LocalvarDefinitionConcern

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
    raise 'no index' unless index
    output.comment("var #{index} #{identifier}")
    output.print('PUSH_VAR', index)
  end

  def formatted_source(_options)
    real_identifier
  end
end
