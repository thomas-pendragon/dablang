require_relative 'node.rb'

class DabNodeNop < DabNode
  def compile(output)
    output.print('NOP')
  end
end
