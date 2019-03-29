class PostprocessDecompiled
  def run(fun)
    counter = 0
    while true
      counter += 1
      next if RemoveNextJumps.new.run(fun)
      next if MergeBlocks.new.run(fun)
      next if RemoveEmptyBlocks.new.run(fun)
      next if RemoveUnreachable.new.run(fun)

      break
    end
    counter != 1
  end
end
