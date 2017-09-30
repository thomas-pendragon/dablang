module RegisterSetterConcern
  def returns_value?
    false
  end

  def users
    function.all_nodes([DabNodeSSAGet, DabNodeRegisterGet]).select do |node|
      node.input_register == self.output_register
    end
  end

  def rename(target_register)
    list = users
    @output_register = target_register
    list.each do |node|
      node.input_register = target_register
    end
  end
end
