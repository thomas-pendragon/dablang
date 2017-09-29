require_relative 'node.rb'
require_relative '../processors/check_return_type.rb'
require_relative '../processors/uncomplexify.rb'

class DabNodeReturn < DabNode
  check_with CheckReturnType
  lower_with Uncomplexify

  def initialize(value)
    super()
    insert(value)
  end

  def value
    self[0]
  end

  def compile(output)
    if $no_autorelease
      self.active_registers.each do |register|
        reg = "R#{register}"
        output.printex(self, 'Q_RELEASE', reg) unless reg == value.register_string
      end
    end
    output.printex(self, 'Q_RETURN', value.register_string)
  end

  def formatted_source(options)
    'return ' + value.formatted_source(options)
  end

  def returns_value?
    false
  end

  def uncomplexify_args
    [value]
  end

  def accepts?(arg)
    arg.register? || arg.literal_nil?
  end
end
