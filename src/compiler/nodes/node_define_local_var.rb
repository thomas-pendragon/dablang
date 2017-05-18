require_relative 'node_set_local_var.rb'

class DabNodeDefineLocalVar < DabNodeSetLocalVar
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
end
