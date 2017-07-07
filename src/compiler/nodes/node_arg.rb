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
    function&.arg_type(@index) || DabTypeAny.new
  end

  def compile(output)
    output.print('PUSH_ARG', @index)
  end

  def compile_local_set(output, index)
    output.print('SETV_ARG', index, @index)
  end
end
