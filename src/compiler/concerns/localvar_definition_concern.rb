module LocalvarDefinitionConcern
  def var_definition
    @var_definition ||= function.all_nodes(DabNodeDefineLocalVar).detect do |node|
      node.identifier == self.identifier
    end
  end

  def index
    var_definition&.index
  end
end
