require_relative 'node.rb'

class DabNodeLiteralBoolean < DabNode
  attr_reader :boolean
  def initialize(boolean)
    super()
    @boolean = boolean
  end

  def extra_dump
    boolean.to_s
  end

  def compile(output)
    output.print(@boolean ? 'PUSH_TRUE' : 'PUSH_FALSE')
  end

  def extra_value
    extra_dump
  end

  def formatted_source(_options)
    extra_dump
  end

  def constant?
    true
  end
end
