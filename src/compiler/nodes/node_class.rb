require_relative 'node'

class DabNodeClass < DabNode
  lower_with Uncomplexify

  attr_reader :identifier

  def initialize(identifier, template_list: nil)
    super()
    @identifier = identifier
    insert(template_list) if template_list
  end

  def template_list
    self[0]
  end

  def extra_dump
    identifier
  end

  def number
    root.class_number(@identifier)
  end

  def compile_as_ssa(output, output_register)
    raise "no class for <#{@identifier}>" unless number

    output.comment(@identifier)
    if template_list

      list = template_list.map(&:input_register).map { |arg| "R#{arg}" }

      args = [
        output_register.nil? ? 'RNIL' : "R#{output_register}",
        number,
        list,
      ]

      output.print('LOAD_CLASS_EX', *args)
    else
      output.print('LOAD_CLASS', "R#{output_register}", number)
    end
  end

  def uncomplexify_args
    return [] unless template_list

    template_list[0..-1]
  end

  def accepts?(arg)
    arg.register?
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

  def actual_type
    constant_value
  end

  def my_type
    DabTypeClass.new
  end

  def my_class_type
    DabTypeClassInstance.new(identifier, root: root)
  end
end
