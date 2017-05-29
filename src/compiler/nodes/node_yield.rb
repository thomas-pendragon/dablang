require_relative 'node.rb'

class DabNodeYield < DabNode
  def compile(output)
    output.printex(self, 'YIELD')
  end

  def formatted_source(_options)
    'yield;'
  end
end
