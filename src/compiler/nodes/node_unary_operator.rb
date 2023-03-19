require_relative 'node'
require_relative '../processors/uncomplexify'

class DabNodeUnaryOperator < DabNode
  lower_with Uncomplexify
  late_lower_with :convert_to_call

  def initialize(value, method)
    super()
    insert(method)
    insert(value)
  end

  def identifier
    self[0]
  end

  def value
    self[1]
  end

  def uncomplexify_args
    [value]
  end

  def formatted_source(options)
    "#{identifier.extra_value}(#{value.formatted_source(options)})"
  end

  def accepts?(arg)
    arg.register?
  end

  def convert_to_call
    identifier_ = identifier.extra_value
    value_ = value
    value_.extract
    call = DabNodeInstanceCall.new(value_, identifier_, DabNode.new, nil)
    replace_with!(call)
    true
  end
end
