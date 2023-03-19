require_relative 'node_basecall'
require_relative '../processors/extract_call_block'

class DabNodeExternalBasecall < DabNodeBasecall
  after_init ExtractCallBlock
end
