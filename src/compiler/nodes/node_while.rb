require_relative 'node.rb'
require_relative '../processors/flatten_while.rb'

class DabNodeWhile < DabNode
  flatten_with FlattenWhile

  def initialize(condition, on_block)
    super()
    insert(condition, 'condition')
    insert(on_block, 'true')
  end

  def condition
    self[0]
  end

  def on_block
    self[1]
  end

  def formatted_source(options)
    ret = 'while (' + condition.formatted_source(options) + ")\n"
    ret += "{\n"
    ret += _indent(on_block.formatted_source(options))
    ret += '}'
    ret
  end

  def formatted_skip_semicolon?
    true
  end
end
