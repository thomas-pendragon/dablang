require_relative 'node.rb'
require_relative '../processors/ssa_prune_unused_setter.rb'
require_relative '../processors/ssa_fold_rename.rb'
require_relative '../concerns/register_setter_concern.rb'

class DabNodeSSASet < DabNode
  include RegisterSetterConcern

  attr_accessor :output_register
  attr_accessor :output_varname

  ssa_optimize_with SSAPruneUnusedSetter
  ssa_optimize_with SSAFoldRename

  def initialize(value, output_register, output_varname = nil)
    super()
    insert(value)
    @output_register = output_register
    @output_varname = output_varname
  end

  def value
    @children[0]
  end

  def extra_dump
    "R#{output_register}= [#{output_varname}] (#{users.count} users)"
  end

  def constant_value?
    value.constant?
  end

  def replace_with_register_set!
    value_ = value.extract
    new_node = DabNodeRegisterSet.new(value_, @output_register, @output_varname)
    replace_with!(new_node)
  end

  def used_in_phi_node?
    !!function.all_nodes(DabNodeSSAPhi).detect do |node|
      node.input_registers.include? output_register
    end
  end

  def formatted_source(options)
    "SR#{output_register} = " + value.formatted_source(options)
  end
end
