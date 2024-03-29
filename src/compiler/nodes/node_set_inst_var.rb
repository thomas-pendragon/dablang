require_relative 'node'
require_relative '../processors/uncomplexify'

class DabNodeSetInstVar < DabNode
  lower_with Uncomplexify

  def initialize(identifier, value)
    super()
    insert(identifier[1..-1])
    insert(value)
  end

  def extra_dump
    "<#{identifier}>"
  end

  def node_identifier
    self[0]
  end

  def value
    self[1]
  end

  def identifier
    "@#{node_identifier.extra_value}"
  end

  def compile(output)
    reg = value.input_register
    output.comment("#{identifier}=")
    output.printex(self, 'SET_INSTVAR', node_identifier.symbol_arg, "R#{reg}")
  end

  def formatted_source(options)
    "#{identifier} = #{value.formatted_source(options)}"
  end

  def returns_value?
    false
  end

  def uncomplexify_args
    [value]
  end

  def accepts?(arg)
    arg.register?
  end
end

class DabNodeSetClassVar < DabNode
  lower_with Uncomplexify

  def initialize(identifier, value)
    super()
    insert(identifier[2..-1])
    insert(value)
  end

  def extra_dump
    "<#{identifier}>"
  end

  def node_identifier
    self[0]
  end

  def value
    self[1]
  end

  def identifier
    "@@#{node_identifier.extra_value}"
  end

  def compile(output)
    reg = value.input_register
    output.comment("#{identifier}=")
    output.printex(self, 'SET_CLASSVAR', node_identifier.symbol_arg, "R#{reg}")
  end

  def formatted_source(options)
    "#{identifier} = #{value.formatted_source(options)}"
  end

  def returns_value?
    false
  end

  def uncomplexify_args
    [value]
  end

  def accepts?(arg)
    arg.register?
  end
end
