require_relative 'node_tree_block'

class DabNodeBreak < DabNodeTreeBlock
  attr_reader :target

  def initialize
    super
    @target = nil
  end

  def bind_to!(target)
    unless target.is_a?(DabNodeBasicBlock)
      raise ArgumentError.new('DabNodeBreak requires a basic-block target')
    end
    raise ArgumentError.new('DabNodeBreak is already bound') if @target

    @target = target
  end

  def build_from_tree(current_block, blocks)
    raise ArgumentError.new('DabNodeBreak requires an enclosing while') unless @target

    current_block << DabNodeJump.new(@target)
    DabNodeBasicBlock.new.tap do |continuation|
      blocks << continuation
    end
  end

  def formatted_source(_options)
    'break'
  end
end
