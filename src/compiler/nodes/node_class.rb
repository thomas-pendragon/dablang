require_relative 'node.rb'

class DabNodeClass < DabNode
  attr_reader :identifier

  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def extra_dump
    identifier
  end

  def number
    root.class_number(@identifier)
  end

  def compile(output)
    raise "no class for <#{@identifier}>" unless number
    output.comment(@identifier)
    output.print('PUSH_CLASS', number)
  end

  def compile_as_ssa(output, output_register)
    raise "no class for <#{@identifier}>" unless number
    output.comment(@identifier)
    output.print('Q_RELEASE', "R#{output_register}") if $no_autorelease
    output.print('Q_SET_CLASS', "R#{output_register}", number)
  end

  def formatted_source(_options)
    extra_dump
  end

  def constant?
    true
  end

  def constant_value
    DabType.parse(identifier)
  end

  def my_type
    DabTypeClass.new
  end
end
