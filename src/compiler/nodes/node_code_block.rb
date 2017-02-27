require_relative 'node.rb'

class DabNodeCodeBlock < DabNode
  def compile(output)
    @children.each do |child|
      child.compile(output)
    end
  end
end
