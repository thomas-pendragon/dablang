require_relative 'node.rb'

class DabNodeBasecall < DabNode
  def initialize(arglist)
    super()
    arglist&.each { |arg| insert(arg) }
  end

  def args
    self[0..-1]
  end

  def block
    nil
  end

  def has_block?
    block && !block.is_a?(DabNodeLiteralNil)
  end

  def _formatted_arguments(options)
    args.map { |item| item.formatted_source(options) }.join(', ')
  end

  def formatted_block(options)
    return '' unless has_block?
    block.formatted_source(options)
  end

  def target_function
    @target_function_cache ||= root.has_function?(real_identifier)
  end

  def mutate!
    super
    @target_function_cache = nil
  end
end
