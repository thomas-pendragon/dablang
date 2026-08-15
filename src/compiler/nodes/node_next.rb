require_relative 'node_tree_block'

class DabNodeNext < DabNodeTreeBlock
  attr_reader :target

  def initialize
    super
    @target = nil
  end

  def bind_to!(target)
    unless target.is_a?(DabNodeBasicBlock)
      raise ArgumentError.new('DabNodeNext requires a basic-block target')
    end
    raise ArgumentError.new('DabNodeNext is already bound') if @target

    @target = target
  end

  def build_from_tree(current_block, blocks)
    raise ArgumentError.new('DabNodeNext requires an enclosing while') unless @target

    current_block << DabNodeJump.new(@target)
    DabNodeBasicBlock.new.tap do |continuation|
      blocks << continuation
    end
  end

  def formatted_source(_options)
    'next'
  end
end
