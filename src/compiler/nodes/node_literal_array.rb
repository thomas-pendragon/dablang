require_relative 'node.rb'

class DabNodeLiteralArray < DabNode
  def initialize(valuelist)
    super()
    insert(valuelist)
  end

  def valuelist
    children[0]
  end

  def compile(output)
    valuelist.each do |node|
      node.compile(output)
    end
    output.print('PUSH_ARRAY', valuelist.count)
  end

  def my_type
    DabTypeArray.new
  end
end
