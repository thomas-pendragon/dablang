class DabPPFixLiterals
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      function.visit_all_and_replace(DabNodeLiteral) do |literal|
        if literal.parent.is_a? DabNodeConstant
          literal
        else
          function.add_constant(literal)
        end
      end
    end
  end
end
