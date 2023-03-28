module LocalvarDefinitionConcern
  def var_definition
    var_definitions&.first
  end

  def box!
    var_definition.box!
  end

  def boxed?
    var_definition&.boxed?
  end

  def var_definitions
    function&.all_nodes(DabNodeDefineLocalVar)&.select do |node|
      node.identifier == self.identifier
    end
  end

  def index
    var_definition&.index
  end
end
