require_relative 'node_literal.rb'

class DabNodeTypedLiteralNumber < DabNodeLiteral
  attr_reader :number
  def initialize(number, type)
    super()
    @number = number
    @my_type = type
  end

  def extra_dump
    number.to_s
  end

  def compile(output)
    case my_type.type_string
    when 'Uint8'
      output.print('PUSH_NUMBER_UINT8', extra_value)
    when 'Int32'
      output.print('PUSH_NUMBER_INT32', extra_value)
    when 'Uint32'
      output.print('PUSH_NUMBER_UINT32', extra_value)
    else
      raise "cannot compile typed number [#{my_type.type_string}]"
    end
  end

  def extra_value
    number.value
  end

  def my_type
    @my_type
  end

  def constant_value
    @number
  end
end
