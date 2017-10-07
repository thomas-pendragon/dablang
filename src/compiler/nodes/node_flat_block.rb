require_relative 'node.rb'

class DabNodeFlatBlock < DabNode
  def compile(output)
    @children.each { |child| child.compile(output) }
  end

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) }
    lines.join("\n")
  end
end
