require_relative 'node_basecall.rb'
require_relative '../processors/extract_call_block.rb'

class DabNodeExternalBasecall < DabNodeBasecall
  after_init ExtractCallBlock
end
