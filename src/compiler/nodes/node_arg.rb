require_relative 'node'

class DabNodeArg < DabNode
  attr_reader :index

  def initialize(index, default_value)
    super()
    @index = index
    insert(default_value) if default_value
  end

  def extra_dump
    "$#{@index}"
  end

  def my_type
    function&.arg_type(@index) || DabTypeObject.new
  end

  def default_value
    self[0]
  end

  def compile_as_ssa(output, output_register)
    output.comment(function&.arg_name(@index))

    if default_value
      output.print('LOAD_ARG_DEFAULT', "R#{output_register}", @index, default_value.register_string)
    else
      output.print('LOAD_ARG', "R#{output_register}", @index)
    end

    if $no_autorelease
      output.printex(self, 'RETAIN', "R#{output_register}")
    end
  end

  def no_side_effects?
    true
  end

  def formatted_source(_options)
    function.arglist[index].identifier
  end
end
