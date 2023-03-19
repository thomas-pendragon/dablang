require_relative 'node'

class DabNodeNop < DabNode
  def compile(output)
    output.print('NOP')
  end
end
