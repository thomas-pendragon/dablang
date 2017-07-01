require_relative 'node.rb'

class DabNodeHasBlock < DabNode
  def compile(output)
    output.printex(self, 'PUSH_HAS_BLOCK')
  end
end
