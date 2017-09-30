require_relative 'node.rb'

class DabNodeLiteralBoolean < DabNode
  attr_reader :boolean
  def initialize(boolean)
    super()
    @boolean = boolean
  end

  def extra_dump
    boolean.to_s
  end

  def compile(output)
    output.print(@boolean ? 'PUSH_TRUE' : 'PUSH_FALSE')
  end

  def compile_as_ssa(output, output_register)
    output.print('Q_RELEASE', "R#{output_register}") if $no_autorelease
    output.printex(self, 'Q_SET_' + (@boolean ? 'TRUE' : 'FALSE'), "R#{output_register}")
  end

  def extra_value
    extra_dump
  end

  def formatted_source(_options)
    extra_dump
  end

  def constant?
    true
  end

  def constant_value
    @boolean
  end
end
