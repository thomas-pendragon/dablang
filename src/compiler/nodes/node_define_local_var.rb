require_relative 'node_set_local_var.rb'

class DabNodeDefineLocalVar < DabNodeSetLocalVar
  def var_uses
    ret = []
    function.visit_all(DabNodeSetLocalVar) do |local_var|
      next if local_var == self
      ret << local_var if local_var.identifier == self.identifier
    end
    function.visit_all(DabNodeLocalVar) do |local_var|
      ret << local_var if local_var.var_definition == self
    end
    ret
  end

  def formatted_source(options)
    'var ' + super
  end
end
