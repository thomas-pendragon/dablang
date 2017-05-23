require_relative 'node.rb'
require_relative '../concerns/localvar_definition_concern.rb'

class DabNodeLocalVar < DabNode
  include LocalvarDefinitionConcern

  attr_accessor :identifier
  attr_reader :original_identifier

  def initialize(identifier)
    super()
    @identifier = identifier
    @original_identifier = identifier
  end

  def extra_dump
    "<#{real_identifier}> [#{index}]"
  end

  def real_identifier
    identifier
  end

  def compile(output)
    raise 'no index' unless index
    output.comment("var #{index} #{original_identifier}")
    output.print('PUSH_VAR', index)
  end

  def formatted_source(_options)
    original_identifier
  end
end
