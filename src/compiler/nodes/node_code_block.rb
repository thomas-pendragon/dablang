require_relative 'node.rb'

class DabNodeCodeBlock < DabNode
  def compile(output)
    @children.each do |child|
      child.compile(output)
    end
  end

  def formatted_source(options)
    lines = @children.map { |item| item.formatted_source(options) }
    return '' unless lines.count > 0
    lines.join("\n") + "\n"
  end
end
