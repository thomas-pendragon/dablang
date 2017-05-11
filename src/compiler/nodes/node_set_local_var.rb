require_relative 'node.rb'
require_relative '../processors/check_assign_type.rb'
require_relative '../concerns/localvar_definition_concern.rb'
require_relative '../processors/strip_readonly_argvars.rb'

class DabNodeSetLocalVar < DabNode
  include LocalvarDefinitionConcern

  attr_reader :identifier
  attr_reader :my_type
  attr_accessor :arg_var

  check_with CheckAssignType
  optimize_with StripReadonlyArgvars

  def initialize(identifier, value, type = nil, arg_var = false)
    super()
    @identifier = identifier
    insert(value || DabNodeLiteralNil.new)
    type ||= DabNodeType.new(nil)
    type = type.dab_type if type.is_a? DabNodeType
    @my_type = type
    @arg_var = arg_var
  end

  def extra_dump
    "<#{real_identifier}> [#{index}]"
  end

  def value
    children[0]
  end

  def real_identifier
    identifier
  end

  def compile(output)
    raise 'no index' unless index
    value.compile(output)
    output.comment("var #{index} #{identifier}")
    output.printex(self, 'SET_VAR', index)
  end

  def formatted_source(options)
    real_identifier + ' = ' + value.formatted_source(options) + ';'
  end

  def all_setters
    function.all_nodes(DabNodeSetLocalVar).select { |node| node.identifier == self.identifier }
  end

  def all_getters
    function.all_nodes(DabNodeLocalVar).select { |node| node.identifier == self.identifier }
  end

  def unresolved_references
    function.all_nodes(DabNodeReferenceLocalVar).select { |node| node.identifier == self.identifier }
  end
end
