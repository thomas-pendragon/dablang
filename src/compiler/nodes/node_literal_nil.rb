require_relative 'node.rb'

class DabNodeLiteralNil < DabNode
  def compile(output)
    output.print('PUSH_NIL')
  end
end
