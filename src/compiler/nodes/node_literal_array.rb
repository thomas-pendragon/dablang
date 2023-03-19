require_relative 'node'
require_relative '../processors/uncomplexify'

class DabNodeLiteralArray < DabNode
  lower_with Uncomplexify

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

  def compile_as_ssa(output, output_register)
    list = items.map(&:register_string)
    output.print('NEW_ARRAY', "R#{output_register}", *list)
  end

  def my_type
    DabTypeArray.new
  end

  def formatted_source(options)
    '@[' + items.map { |item| item.formatted_source(options) }.join(', ') + ']'
  end

  def uncomplexify_args
    items
  end

  def accepts?(arg)
    arg.register?
  end
end
