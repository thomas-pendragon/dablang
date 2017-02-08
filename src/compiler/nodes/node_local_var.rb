require_relative 'node.rb'

class DabNodeLocalVar < DabNode
  attr_accessor :index
  attr_accessor :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    @identifier
  end

  def real_identifier
    identifier
  end

  def compile(output)
    raise 'no index' unless @index
    output.comment("var #{index} #{identifier}")
    output.print('PUSH_VAR', index)
  end

  def var_definition
    function.visit_all(DabNodeDefineLocalVar) do |define_var|
      if define_var.real_identifier == self.real_identifier
        return define_var
      end
    end
    nil
  end
end
