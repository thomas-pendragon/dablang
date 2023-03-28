require_relative 'node'
require_relative '../concerns/localvar_definition_concern'

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
    ret = "<#{real_identifier}> [#{index}]"
    if boxed?
      ret += ' [BOXED]'.purple
    end
    if closure_pass?
      ret += ' [CLOSURE PASS]'.purple
    end
    ret
  end

  def real_identifier
    identifier
  end

  def formatted_source(_options)
    original_identifier
  end

  def var_setters
    previous_nodes_in_tree(DabNodeSetLocalVar)&.select do |node|
      node.identifier == self.identifier
    end
  end

  def last_var_setter
    var_setters.last
  end

  def register?
    true
  end
end
