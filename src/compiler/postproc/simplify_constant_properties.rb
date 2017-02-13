class DabPPSimplifyConstantProperties
  def run(program)
    program.visit_all(DabNodePropertyGet) do |node|
      if node.constant?
        simplified = node.simplify_constant
        if simplified
          node.replace_with!(simplified)
        end
      end
    end
  end
end
