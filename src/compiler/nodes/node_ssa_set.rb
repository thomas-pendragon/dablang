require_relative 'node.rb'
require_relative '../processors/ssa_prune_unused_setter.rb'
require_relative '../processors/ssa_fold_rename.rb'

class DabNodeSSASet < DabNode
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
    "R#{output_register}= [#{output_varname}]"
  end

  def compile(output)
    raise 'unsupported value' unless value.respond_to?(:compile_as_ssa)
    value.compile_as_ssa(output, output_register)
  end

  def returns_value?
    false
  end

  def users
    function.all_nodes(DabNodeSSAGet).select do |node|
      node.input_register == self.output_register
    end
  end

  def rename(target_register)
    list = users
    @output_register = target_register
    list.each do |node|
      node.input_register = target_register
    end
  end
end
