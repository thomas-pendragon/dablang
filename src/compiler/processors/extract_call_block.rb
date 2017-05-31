class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    num = 1
    while true
      name = node.function.identifier + "__block#{num}"
      if node.root.has_function?(name)
        num += 1
      else
        break
      end
    end

    fun = DabNodeFunction.new(name, block.body, block.arglist, false)

    fun.init!

    node.root.add_function(fun)
    node.block.replace_with!(DabNodeBlockReference.new(fun))

    true
  end
end
