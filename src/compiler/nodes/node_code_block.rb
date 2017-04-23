require_relative 'node.rb'

class DabNodeCodeBlock < DabNode
  attr_reader :label

  def initialize(label = nil)
    super()
    @label = label
  end

  def extra_dump
    ret = []
    ret << ".#{label}" if label
    ret.join(' ')
  end

  def compile(_output)
    raise 'not compileable'
  end

  def convert_block!
    ret = function.new_codeblock_ex
    children.each do |item|
      ret.insert(item)
    end
    ret
  end

  def blockify!
    if parent.is_a? DabNodeFunction
      convert_block!
      true
    else
      super
    end
  end

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) }
    return '' unless lines.count > 0
    lines.join("\n") + "\n"
  end
end
