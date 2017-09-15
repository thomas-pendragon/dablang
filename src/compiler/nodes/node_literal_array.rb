require_relative 'node.rb'

class DabNodeLiteralArray < DabNode
  def initialize(valuelist)
    super()
    valuelist&.each do |value|
      insert(value)
    end
  end

  def items
    self[0..-1]
  end

  def _compile_items(output)
    items.each do |node|
      node.compile(output)
    end
  end

  def compile(output)
    _compile_items(output)
    output.print('PUSH_ARRAY', items.count)
  end

  def my_type
    DabTypeArray.new
  end

  def formatted_source(options)
    '@[' + items.map { |item| item.formatted_source(options) }.join(', ') + ']'
  end
end
