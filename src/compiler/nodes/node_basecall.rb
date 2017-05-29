require_relative 'node.rb'

class DabNodeBasecall < DabNode
  def initialize(arglist)
    super()
    arglist&.each { |arg| insert(arg) }
  end

  def args
    children
  end

  def _formatted_arguments(options)
    args.map { |item| item.formatted_source(options) }.join(', ')
  end
end
