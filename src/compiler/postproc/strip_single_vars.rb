class DabPPStripSingleVars
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      function.visit_all(DabNodeDefineLocalVar) do |define_var|
        next if define_var.has_errors?
        uses = define_var.var_uses
        if uses.count == 1 && define_var.value.constant?
          var = uses.first
          var.replace_with!(define_var.value)
          define_var.remove!
          function.remove_localvar_index(define_var.index)
        end
      end
    end
  end
end
