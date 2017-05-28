require_relative 'node_set_local_var.rb'
require_relative '../processors/check_multiple_definitions.rb'
require_relative '../processors/add_localvar_postfix.rb'

class DabNodeDefineLocalVar < DabNodeSetLocalVar
  check_with CheckMultipleDefinitions
  after_init AddLocalvarPostfix

  def formatted_source(options)
    var = 'var '
    type = @my_type.type_string
    if type != 'Any'
      var = "var<#{type}> "
    end
    if value.is_a? DabNodeLiteralNil
      "#{var}#{real_identifier};"
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
    list = [self] + following_nodes([DabNodeSetLocalVar, DabNodeLocalVar, DabNodeReferenceLocalVar]) do |node|
      test1 = node != self
      test2 = node.is_a?(DabNodeDefineLocalVar)
      test3 = node.identifier == self.identifier
      test1 && test2 && test3
    end
    list = list.select { |item| item.identifier == self.identifier }
    list
  end
end
