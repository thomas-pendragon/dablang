require_relative 'node_set_local_var'
require_relative '../processors/add_localvar_postfix'

class DabNodeDefineLocalVar < DabNodeSetLocalVar
  late_after_init AddLocalvarPostfix

  def formatted_source(options)
    var = 'var '
    type = @my_type.type_string
    if type != 'Object'
      var = "var<#{type}> "
    end
    if value.is_a? DabNodeLiteralNil
      "#{var}#{real_identifier}"
    else
      "#{var}#{super}"
    end
  end

  def var_definition
    self
  end

  def index
    function&.localvar_index(self)
  end

  def all_users
    _all_users
  end

  def box!
    @boxed = true
  end

  def closure_box!
    @boxed = true
    @closure = true
  end

  def boxed?
    @boxed
  end

  def closure?
    @closure
  end

  def extra_dump
    ret = super
    if @unboxed
    elsif closure?
      ret += ' [CLOSURE]'.purple
    end
    ret
  end

  def all_unscoped_users
    list = [self] + following_nodes([DabNodeSetLocalVar, DabNodeLocalVar, DabNodeReferenceLocalVar], unscoped: true)
    list.select { |item| item.identifier == self.identifier }
  end

  def _all_users
    list = [self] + following_nodes([DabNodeSetLocalVar, DabNodeLocalVar, DabNodeReferenceLocalVar]) do |node|
      test1 = node != self
      test2 = node.is_a?(DabNodeDefineLocalVar)
      test3 = node.identifier == self.identifier
      test1 && test2 && test3
    end
    list.select { |item| item.identifier == self.identifier }
  end
end
