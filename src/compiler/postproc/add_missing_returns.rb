class DabPPAddMissingReturns
  def run(program)
    program.visit_all(DabNodeFunction) do |function|
      body = function.body
      unless body.ends_with? DabNodeReturn
        body.insert(DabNodeReturn.new(DabNodeLiteralNil.new))
      end
    end
  end
end
