class DabNodeCodeBlock < DabNode
  def compile(output)
    @children.each do |child|
      child.compile(output)
    end
  end
end
