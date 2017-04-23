class DabPPAddMissingReturns
  def run(program)
    program.visit_all(DabNodeCodeBlockEx) do |body|
      unless body.ends_with?(DabNodeJump) || body.ends_with?(DabNodeConditionalJump) || body.ends_with?(DabNodeReturn)
        body.insert(DabNodeReturn.new(DabNodeLiteralNil.new))
      end
    end
  end
end
