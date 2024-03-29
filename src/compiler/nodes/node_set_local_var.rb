require_relative 'node'
require_relative '../processors/check_assign_type'
require_relative '../concerns/localvar_definition_concern'
require_relative '../processors/convert_set_value'

class DabNodeSetLocalVar < DabNode
  include LocalvarDefinitionConcern

  attr_accessor :identifier
  attr_reader :my_type
  attr_reader :original_identifier

  check_with CheckAssignType
  after_init ConvertSetValue
  lower_with Uncomplexify
  box_with :box_me

  def initialize(identifier, value, type = nil)
    super()
    @identifier = identifier
    insert(value || DabNodeLiteralNil.new)
    type ||= DabNodeType.new(nil)
    type = type.dab_type if type.is_a? DabNodeType
    @my_type = type
    @original_identifier = identifier
  end

  def extra_dump
    ret = "<#{real_identifier}> [#{index}]"
    if @unboxed
      ret += ' [_box]'
    elsif boxed?
      ret += ' [BOXED]'.purple
    end
    ret
  end

  def uncomplexify_args
    [value]
  end

  def box_me
    return false unless boxed?
    return false if @unboxed
    return false if closure?

    @unboxed = true

    new_value = value.dup
    if setter_only?
      value.replace_with!(DabNodeSetbox.new(new_value, DabNodeLocalVar.new(identifier, force_no_box: true)))
    else
      value.replace_with!(DabNodeBox.new(new_value))
    end

    true
  end

  def closure?
    false
  end

  def value
    self[0]
  end

  def setter_only?
    var_definition != self
  end

  def real_identifier
    identifier
  end

  def formatted_source(options)
    "#{original_identifier} = #{value.formatted_source(options)}"
  end

  def all_setters
    all_users.select { |node| node.is_a? DabNodeSetLocalVar }
  end

  def all_getters
    all_users.select { |node| node.is_a? DabNodeLocalVar }
  end

  def all_unscoped_setters
    all_unscoped_users.select { |node| node.is_a? DabNodeSetLocalVar }
  end

  def all_unscoped_getters
    all_unscoped_users.select { |node| node.is_a? DabNodeLocalVar }
  end

  def all_users
    var_definition.all_users
  end

  def unresolved_references
    all_users.select { |node| node.is_a? DabNodeReferenceLocalVar }
  end

  def returns_value?
    false
  end

  def fixup_ssa(variable, last_setter)
    if variable.identifier == self.identifier
      self
    else
      last_setter
    end
  end
end
