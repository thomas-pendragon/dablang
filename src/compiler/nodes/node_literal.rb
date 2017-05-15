require_relative 'node.rb'
require_relative '../processors/extract_literal.rb'
require_relative '../processors/strip_unused_value.rb'

class DabNodeLiteral < DabNode
  lower_with ExtractLiteral
  lower_with StripUnusedValue

  def constant?
    true
  end
end
