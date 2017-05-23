require_relative 'node_reference.rb'

class DabNodeReferenceLocalVar < DabNodeReference
  attr_reader :name

  def initialize(name)
    super()
    @name = name
  end

  def compiled
    DabNodeLocalVar.new(@name)
  end

  def formatted_source(_options)
    @name
  end

  def extra_dump
    @name
  end

  def identifier
    @name
  end

  def identifier=(value)
    @name = value
  end
end
