require_relative 'node'

class DabNodeType < DabNode
  attr_reader :dab_type

  def initialize(typename)
    super()
    @dab_type = DabType.parse(typename)
  end

  def extra_dump
    @dab_type.class.name
  end

  def extra_value
    extra_dump
  end
end
