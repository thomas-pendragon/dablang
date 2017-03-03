require_relative 'node.rb'

class DabNodeLiteralArray < DabNode
  def compile(output)
    output.print('PUSH_ARRAY', 0)
  end

  def my_type
    DabTypeArray.new
  end
end
