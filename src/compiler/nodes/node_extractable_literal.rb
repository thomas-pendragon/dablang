require_relative 'node_literal.rb'
require_relative '../processors/extract_literal.rb'

class DabNodeExtractableLiteral < DabNodeLiteral
  lower_with ExtractLiteral
end
