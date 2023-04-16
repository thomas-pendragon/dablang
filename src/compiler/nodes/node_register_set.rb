require_relative 'node'
require_relative '../concerns/register_setter_concern'
require_relative '../processors/ssa_prune_unused_setter'

class DabNodeRegisterSet < DabNode
  include RegisterSetterConcern

  # lower_with Uncomplexify
  ssa_optimize_with SSAPruneUnusedSetter
  post_ssa_with :prune_nil!

  unssa_with :unssa!

  attr_accessor :output_register
  attr_accessor :output_varname

  def initialize(value, output_register, output_varname = nil)
    super()
    insert(value)
    @output_register = output_register
    @output_varname = output_varname
  end

  # def uncomplexify_args
  #   [value]
  # end

  def value
    @children[0]
  end

  def extra_dump
    "$R#{output_register}= [#{output_varname}] (#{users.count} users)"
  end

  def compile(output)
    output.print('RELEASE', "R#{output_register}") if true && !first_setter?
    if value.respond_to?(:compile_as_ssa)
      value.compile_as_ssa(output, output_register)
    else
      # value.dump
      function.dump
      raise "cannot compile #{value.class} (no ssa form)"
    end
  end

  def constant_value?
    value.constant?
  end

  def rename(from, to)
    @output_register = to if @output_register == from
  end

  def all_setters
    function.all_nodes(DabNodeRegisterSet).select { |setter| setter.output_register == self.output_register }
  end

  def first_setter?
    all_setters.index(self) == 0
  end

  def formatted_source(options)
    "R#{output_register} = " + value.formatted_source(options)
  end

  def unssa!
    node = DabNodeSetLocalVar.new("r#{output_register}", value.dup)
    replace_with!(node)
    true
  end

  def prune_nil!
    return unless value.is_a? DabNodeLiteralNil
    return if users.count > 0

    remove!
    true
  end

  def my_class_type
    value.my_class_type
  end
end
