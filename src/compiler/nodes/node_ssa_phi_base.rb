require_relative 'node'

class DabNodeSSAPhiBase < DabNode
  attr_accessor :input_nodes

  def initialize(input_nodes)
    super()
    @input_nodes = input_nodes
  end

  def extra_dump
    "#{input_nodes.count} input nodes"
  end

  def fixup_ssa_phi_nodes(setters_mapping)
    registers = input_nodes.map do |node|
      setters_mapping[node].output_register
    end
    identifier = input_nodes.first.identifier
    phi = DabNodeSSAPhi.new(registers, identifier)
    replace_with!(phi)
  end
end
