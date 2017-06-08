require_relative 'node.rb'
require_relative '../processors/check_assign_type.rb'
require_relative '../concerns/localvar_definition_concern.rb'
require_relative '../processors/strip_readonly_argvars.rb'

class DabNodeSetLocalVar < DabNode
  include LocalvarDefinitionConcern

  attr_accessor :identifier
  attr_reader :my_type
  attr_accessor :arg_var
  attr_reader :original_identifier

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
    @original_identifier = identifier
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
    output.comment("var #{index} #{original_identifier}")
    output.printex(self, 'SET_VAR', index)
  end

  def formatted_source(options)
    original_identifier + ' = ' + value.formatted_source(options)
  end

  def all_setters
    all_users.select { |node| node.is_a? DabNodeSetLocalVar }
  end

  def all_getters
    all_users.select { |node| node.is_a? DabNodeLocalVar }
  end

  def all_users
    var_definition.all_users
  end

  def unresolved_references
    all_users.select { |node| node.is_a? DabNodeReferenceLocalVar }
  end
end
