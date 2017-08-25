require_relative 'node.rb'
require_relative '../processors/store_locally.rb'

class DabNodeArg < DabNode
  include NodeStoredLocally

  attr_reader :index

  def initialize(index)
    super()
    @index = index
  end

  def extra_dump
    "$#{@index}"
  end

  def my_type
    function&.arg_type(@index) || DabTypeObject.new
  end

  def compile(output)
    output.print('PUSH_ARG', @index)
  end

  def compile_local_set(output, index)
    output.print('SETV_ARG', index, @index)
  end

  def compile_as_ssa(output, output_register)
    output.comment(function&.arg_name(@index))
    output.print('Q_SET_ARG', "R#{output_register}", @index)
  end
end
