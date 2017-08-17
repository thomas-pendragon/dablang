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

  def var_setters
    previous_nodes(DabNodeSetLocalVar)&.select do |node|
      node.identifier == self.identifier
    end
  end

  def last_var_setter
    var_setters.last
  end
end
