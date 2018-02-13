class PostprocessDecompiled
  def run(fun)
    RemoveNextJumps.new.run(fun)
    MergeBlocks.new.run(fun)
    RemoveEmptyBlocks.new.run(fun)
    RemoveUnreachable.new.run(fun)
  end
end
