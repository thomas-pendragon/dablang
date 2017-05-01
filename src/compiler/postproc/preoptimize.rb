class DabPPPreoptimize
  def run(program)
    while program.preoptimize!
    end
  end
end
