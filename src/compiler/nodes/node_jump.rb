require_relative 'node.rb'

class DabNodeJump < DabNode
  attr_reader :target
  def initialize(target)
    super()
    @target = target
  end

  def extra_dump
    "->#{target.label}"
  end

  def condition
    children[0]
  end

  def compile(output)
    output.print('JMP', target.label)
  end
end
