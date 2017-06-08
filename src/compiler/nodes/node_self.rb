require_relative 'node.rb'

class DabNodeSelf < DabNode
  def compile(output)
    output.print('PUSH_SELF')
  end

  def formatted_source(_options)
    'self'
  end
end
