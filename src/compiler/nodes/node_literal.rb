require_relative 'node.rb'
require_relative '../processors/extract_literal.rb'

class DabNodeLiteral < DabNode
  lower_with ExtractLiteral

  def constant?
    true
  end
end
