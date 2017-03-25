require_relative 'node.rb'

class DabNodeCodeBlock < DabNode
  attr_reader :label

  def initialize(label = nil)
    super()
    @label = label
  end

  def extra_dump
    ".#{label}" if label
  end

  def compile(output)
    output.label(label) if label
    if label && empty?
      output.print('NOP')
    else
      @children.each do |child|
        child.compile(output)
      end
    end
  end

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) }
    return '' unless lines.count > 0
    lines.join("\n") + "\n"
  end

  def empty?
    @children.empty? || @children.all?(&:empty?)
  end
end
