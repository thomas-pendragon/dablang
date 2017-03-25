require_relative 'node.rb'

class DabNodeJump < DabNode
  attr_reader :target
  def initialize(target, condition = nil)
    super()
    @target = target
    insert(condition) if condition
  end

  def extra_dump
    "->#{target} #{condition ? 'if not' : ''}"
  end

  def condition
    children[0]
  end

  def compile(output)
    if condition
      condition.compile(output)
      output.print('JMP_IFN', target)
    else
      output.print('JMP', target)
    end
  end
end
