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

  def lower!
    return blockify! if has_subblocks? && !only_has_subblocks?
    return unlabelify! if has_subblocks? && has_label?
    super
  end

  def blockify!
    @children = @children.map do |child|
      if !child.is_a?(DabNodeCodeBlock)
        block = DabNodeCodeBlock.new
        block.insert(child)
        claim(block)
      else
        child
      end
    end
    true
  end

  def unlabelify!
    first_label = DabNodeCodeBlock.new(self.label)
    @children.unshift(first_label)
    replace_with!(@children)
    true
  end

  def has_label?
    !!label
  end

  def only_has_subblocks?
    @children.all? { |item| item.is_a? DabNodeCodeBlock }
  end

  def has_subblocks?
    @children.any? { |item| item.is_a? DabNodeCodeBlock }
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
