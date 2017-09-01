require_relative 'node.rb'

class DabNodeFlatBlock < DabNode
  def compile(output)
    @children.each { |child| child.compile(output) }
  end
end
