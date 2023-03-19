require_relative 'node_literal'
require_relative '../processors/extract_literal'

class DabNodeExtractableLiteral < DabNodeLiteral
  lower_with ExtractLiteral
end
